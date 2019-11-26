#define CHAMELEON_NO_EXPIRE -1

/datum/chameleon_appearance
	var/datum/atom_hud/alternate_appearance/shared/hud
	var/list/datum/component/chameleon/active_components
	var/id
	var/static/cham_id = 0
	var/copypath
	var/timer = CHAMELEON_NO_EXPIRE //in minutes, set to CHAMELEON_NO_EXPIRE to disable the component's expiration time.
	var/name
	var/desc
	var/gender
	var/worn_layer
	var/mutable_appearance/right_inhand
	var/mutable_appearance/left_inhand
	var/image/holo_mask
	var/image/alt_holo_mask
	var/end_visual = /obj/effect/temp_visual/decoy/fading/halfsecond //the temporary visual spawned whenever one of the components is removed.
	var/disruptable = TRUE //wheter attacking and other sort of things will disrupt the

/datum/chameleon_appearance/New(atom/A, datum/atom_hud/alternate_appearance/shared/C, _timer, _holo_mask, _alt_holo_mask)
	hud = C || GLOB.huds[ALT_APPEARANCE_HUD_CHAMELEON]
	id = "cham_[++cham_id]"
	timer = _timer || timer
	holo_mask = image('icons/effects/effects.dmi', _holo_mask)
	alt_holo_mask = image('icons/effects/effects.dmi', _alt_holo_mask)
	if(A)
		disguise_as(A)

/datum/chameleon_appearance/proc/disguise_as(atom/A)
	copypath = A.type
	name = A.name
	gender = A.gender
	hud.register_appearance(A, id)
	var/mob/living/carbon/human/dummy/mannequin = generate_or_wait_for_human_dummy(DUMMY_HUMAN_SLOT_EXAMINE, FALSE)
	desc = A.examine(mannequin)
	if(isitem(A)) //registering easy inhands disguises here.
		var/obj/item/I = A
		var/worn_state = I.item_state || I.icon_state
		worn_layer = I.alternate_worn_layer
		left_inhand = I.build_worn_icon(worn_state, HANDS_LAYER, I.lefthand_file, TRUE)
		hud.register_appearance(left_inhand, create_copy = TRUE)
		right_inhand = I.build_worn_icon(worn_state, HANDS_LAYER, I.righthand_file, TRUE)
		hud.register_appearance(right_inhand, create_copy = TRUE)

/datum/chameleon_appearance/Destroy()
	for(var/A in active_components)
		var/datum/component/chameleon/C = A
		qdel(C, FALSE, end_visual)
	hud.unregister_appearance(id)
	if(left_inhand)
		hud.unregister_appearance(left_inhand) //it'll delete them.
	if(right_inhand)
		hud.unregister_appearance(right_inhand) //idem
	return ..()

////////////////////////////////////////

/datum/component/chameleon //not to be confused with chameleon clothing.
	var/datum/chameleon_appearance/cham
	var/image/disguise
	var/prev_name
	var/lifespan = CHAMELEON_NO_EXPIRE
	var/timer_id
	var/expiration_date
	var/anim_busy = FALSE
	var/disruptable = TRUE
	var/image/active_inhand

/datum/component/chameleon/Initialize(datum/chameleon_appearance/CA)
	if(!ismovableatom(parent) || !CA || !istype(CA))
		return COMPONENT_INCOMPATIBLE
	disguise = CA.hud.add_to_hud(parent, CA.id, CA.holo_mask, CA.alt_holo_mask)
	if(!disguise)
		return COMPONENT_INCOMPATIBLE
	LAZYADD(CA.active_components, src)
	cham = CA
	RegisterSignal(CA, COMSIG_PARENT_PREQDELETED, .proc/unmodify)
	disruptable = CA.disruptable
	lifespan = CA.timer
	if(lifespan != CHAMELEON_NO_EXPIRE)
		expiration_date = world.time + lifespan
		timer_id = addtimer(CALLBACK(src, .proc/unmodify), lifespan, TIMER_UNIQUE|TIMER_OVERRIDE|TIMER_NO_HASH_WAIT|TIMER_STOPPABLE)

/datum/component/chameleon/RegisterWithParent()
	var/atom/movable/A = parent
	if(disruptable)
		RegisterSignal(A, COMSIG_ATOM_EMP_ACT, .proc/disrupt_emp)
		RegisterSignal(A, COMSIG_ATOM_EX_ACT, .proc/disrupt_ex_act)
	if(isobj(A))
		if(disruptable)
			RegisterSignal(A, COMSIG_OBJ_TAKE_DAMAGE, .proc/disrupt_damage)
		if(isitem(A))
			if(disruptable)
				RegisterSignal(A, COMSIG_ITEM_ATTACK, .proc/disrupt_attack)
			if(ispath(cham.copypath, /obj/item))
				RegisterSignal(A, COMSIG_ITEM_EQUIPPED, .proc/unmodify_if_worn) //we aren't going past inhands right now.
				RegisterSignal(A, COMSIG_ITEM_BUILD_WORN_ICON, .proc/build_held_cham)
			else //bulky objects can't be normally held anyway, and also lack inhands.
				RegisterSignal(A, COMSIG_ITEM_EQUIPPED, .proc/unmodify)
	prev_name = A.name
	A.name = cham.name
	RegisterSignal(A, COMSIG_PARENT_PRE_EXAMINE, .proc/cham_examine)
	RegisterSignal(A, COMSIG_ATOM_GET_EXAMINE_NAME, .proc/cham_article)

/datum/component/chameleon/UnregisterFromParent()
	UnregisterSignal(parent, list(COMSIG_ATOM_EMP_ACT, COMSIG_ATOM_EX_ACT, COMSIG_OBJ_TAKE_DAMAGE, COMSIG_ITEM_ATTACK,
								COMSIG_ITEM_EQUIPPED, COMSIG_PARENT_PRE_EXAMINE, COMSIG_ATOM_GET_EXAMINE_NAME,
								COMSIG_ITEM_BUILD_WORN_ICON))

/datum/component/chameleon/Destroy(forced = FALSE, _end_visual)
	STOP_PROCESSING(SSobj, src)
	if(cham)
		LAZYREMOVE(cham.active_components, src)
	var/atom/movable/A = parent
	var/end_visual = _end_visual || cham?.end_visual
	if(end_visual && !QDELETED(A))
		new end_visual (get_turf(A), disguise)
		A.name = prev_name
	return ..()

/datum/component/chameleon/proc/unmodify()
	if(!QDELETED(src))
		qdel(src)

/datum/component/chameleon/proc/unmodify_if_worn(datum/source, mob/equipper, slot)
	var/allowed_slots = SLOT_GENERC_DEXTROUS_STORAGE|SLOT_IN_BACKPACK|SLOT_S_STORE|SLOT_R_STORE|SLOT_L_STORE|SLOT_HANDS
	if(!CHECK_BITFIELD(allowed_slots, slotdefine2slotbit(slot)))
		qdel(src)

/datum/component/chameleon/vv_edit_var(var_name, var_value)
	var/old_lifespan = lifespan
	var/old_disruptable = disruptable
	. = ..()
	if(!.)
		return
	switch(var_name)
		if(NAMEOF(src, disruptable))
			if(var_value == old_disruptable)
				return
			if(!var_value)
				UnregisterSignal(parent, list(COMSIG_ATOM_EMP_ACT, COMSIG_ATOM_EX_ACT, COMSIG_OBJ_TAKE_DAMAGE, COMSIG_ITEM_ATTACK))
			else
				RegisterSignal(parent, COMSIG_ATOM_EMP_ACT, .proc/disrupt_emp)
				RegisterSignal(parent, COMSIG_ATOM_EX_ACT, .proc/disrupt_ex_act)
				if(isobj(parent))
					RegisterSignal(parent, COMSIG_OBJ_TAKE_DAMAGE, .proc/disrupt_damage)
					if(isitem(parent))
						RegisterSignal(parent, COMSIG_ITEM_ATTACK, .proc/disrupt_attack)
		if(NAMEOF(src, old_lifespan))
			if(var_value == old_lifespan)
				return
			if(var_value == CHAMELEON_NO_EXPIRE)
				deltimer(timer_id)
				timer_id = null
				return
			recalculate_time_left(lifespan - old_lifespan)

/datum/component/chameleon/proc/cham_examine(mob/source)
	if(cham.hud.mobShouldSee(source))
		to_chat(source, cham.desc)
		return COMPONENT_STOP_EXAMINE

/datum/component/chameleon/proc/cham_article(datum/source, mob/M, list/overrides)
	if(cham.hud.mobShouldSee(source))
		overrides[EXAMINE_POSITION_ARTICLE] = cham.gender == PLURAL ? "some" : "a"
		return COMPONENT_EXNAME_CHANGED

/datum/component/chameleon/proc/build_held_cham(datum/source, mutable_appearance/standing, list/offsets, state, default_layer, default_icon_file, isinhands, femaleuniform)
	var/obj/item/I = parent
	if(!isinhands || !ismob(I.loc))
		return
	var/mob/M = I.loc
	var/left_rights = M.get_held_index_of_item(I) % 2
	active_inhand = cham.hud.add_to_hud(standing, left_rights ?  cham.left_inhand : cham.right_inhand, cham.holo_mask, cham.alt_holo_mask)
	active_inhand.layer = cham.worn_layer || M.get_hands_layer()

/datum/component/chameleon/proc/disrupt_anim()
	if(anim_busy)
		return
	anim_busy = TRUE
	var/A1 = max(disguise.alpha - rand(30, 50), 0)
	var/A2 = disguise.alpha
	var/C1 = list(rgb(77,77,77), rgb(150,150,150), rgb(28,28,28), rgb(0,0,0))
	var/C2 = disguise.color
	for(var/A in list(disguise, active_inhand))
		var/image/I = A
		if(I?.override)
			I.override = FALSE
			addtimer(VARSET_CALLBACK(I, override, TRUE), 1)
			addtimer(VARSET_CALLBACK(I, override, FALSE), 2)
			addtimer(VARSET_CALLBACK(I, override, TRUE), 3)
	animate(disguise, alpha = A1, color = C1, time = 2)
	animate(disguise, alpha = A2, color = C2, time = 2)
	addtimer(VARSET_CALLBACK(src, anim_busy, FALSE), 8)

/datum/component/chameleon/proc/disrupt_ex_act(datum/source, severity, target)
	if(!anim_busy)
		INVOKE_ASYNC(src, .proc/disrupt_anim)
	recalculate_time_left(1.5 MINUTES * severity)

/datum/component/chameleon/proc/disrupt_emp(datum/source, severity)
	INVOKE_ASYNC(src, .proc/disrupt_anim)
	recalculate_time_left(2 MINUTES * severity)

/datum/component/chameleon/proc/disrupt_damage(datum/source, damage_amount, damage_type, damage_flag, attack_dir, armour_penetration)
	INVOKE_ASYNC(src, .proc/disrupt_anim)
	recalculate_time_left(3 SECONDS * damage_amount)

/datum/component/chameleon/proc/disrupt_attack(datum/source, mob/living/target, mob/living/user)
	var/obj/O = parent
	INVOKE_ASYNC(src, .proc/disrupt_anim)
	recalculate_time_left(20 + 2 SECONDS * O.force)

/datum/component/chameleon/proc/recalculate_time_left(modifier)
	if(lifespan == CHAMELEON_NO_EXPIRE)
		return
	expiration_date += modifier
	var/new_lifespan = expiration_date - world.time
	if(new_lifespan < 0)
		if(!QDELETED(src))
			qdel(src)
		return
	timer_id = addtimer(CALLBACK(src, .proc/unmodify), new_lifespan, TIMER_UNIQUE|TIMER_OVERRIDE|TIMER_NO_HASH_WAIT|TIMER_STOPPABLE)

#undef CHAMELEON_NO_EXPIRE
