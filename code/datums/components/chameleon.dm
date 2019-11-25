#define CHAMELEON_NO_EXPIRE -1

/datum/chameleon_disguise
	var/datum/atom_hud/alternate_appearance/shared/chameleon/hud
	var/id
	var/static/cham_id
	var/timer = 20 MINUTES //set it to CHAMELEON_NO_EXPIRE to disable the component's expiration time.
	var/name
	var/desc
	var/gender
	var/worn_state
	var/worn_layer
	var/righthand_icon
	var/list/right_overlays
	var/lefthand_icon
	var/list/left_overlays
	var/worn_color
	var/worn_alpha
	var/end_visual = /obj/effect/temp_visual/decoy/fading/halfsecond
	var/disruptable = TRUE

/datum/chameleon_disguise/New(atom/A, datum/atom_hud/alternate_appearance/shared/C, _timer)
	hud = C || GLOB.huds[ALT_APPEARANCE_HUD_CHAMELEON]
	id = "cham_[++cham_id]"
	timer = _timer || timer
	if(A)
		name = A.name
		gender = A.gender
		C.register_appearance(A, id)
		var/mob/living/carbon/human/dummy/mannequin = generate_or_wait_for_human_dummy(DUMMY_HUMAN_SLOT_EXAMINE, FALSE)
		desc = A.examine(mannequin)
		if(isitem(A))
			var/obj/item/I = A
			worn_state = I.item_state || I.icon_state
			worn_layer = I.alternate_worn_layer
			righthand_icon = I.righthand_file
			right_overlays = worn_overlays(TRUE, righthand_icon)
			lefthand_icon = I.lefthand_file
			left_overlays = worn_overlays(TRUE, lefthand_icon)
			worn_color = I.color
			worn_alpha = I.alpha

/datum/chameleon_disguise/Destroy()
	if(left_overlays)
		QDEL_NULL(left_overlays)
	if(right_overlays)
		QDEL_NULL(right_overlays)
	hud = null

////////////////////////////////////////

/datum/component/chameleon //not to be confused with chameleon clothing.
	var/datum/chameleon_disguise/disguise
	var/image/appearance
	var/prev_name
	var/time_left
	var/timer_id
	var/expiration_date
	var/anim_busy = FALSE

/datum/component/chameleon/Initialize(datum/chameleon_disguise/D, holo_mask, alt_holo_mask)
	if(!ismovableatom(parent) || !D || !istype(D) || !D.hud)
		return COMPONENT_INCOMPATIBLE
	var/list/arguments = list(parent, disguise) + args.Copy(2)
	appearance = D.hud.add_to_hud(arglist(arguments))
	if(!appearance)
		return COMPONENT_INCOMPATIBLE
	disguise = D
	RegisterSignal(D, COMSIG_PARENT_PREQDELETED, .proc/unmodify)
	description = D.desc
	alt_name = D.name
	disruptable = D.disruptable
	end_visual = D.end_visual
	time_left = D.timer
	if(time_left != CHAMELEON_NO_EXPIRE)
		expiration_date = world.time + time_left
		timer_id = addtimer(CALLBACK(src, .proc/unmodify) time_left, TIMER_UNIQUE|TIMER_OVERRIDE|TIMER_NO_HASH_WAIT|TIMER_STOPPABLE)

/datum/component/chameleon/RegisterWithParent()
	var/atom/movable/A = parent
	if(disruptable)
		RegisterSignal(A, COMSIG_ATOM_EMP_ACT, .proc/disrupt_emp)
		RegisterSignal(A, COMSIG_ATOM_EX_ACT, .proc/disrupt_ex_act)
		if(isobj(A))
			RegisterSignal(A, COMSIG_OBJ_TAKE_DAMAGE, .proc/disrupt_obj)
			if(isitem(A))
				RegisterSignal(A, COMSIG_ITEM_ATTACK, .proc/disrupt_item)
				RegisterSignal(A, COMSIG_ITEM_EQUIPPED, .proc/unmodify_if_worn) //we aren't going past inhands.
				RegisterSignal(A, COMSIG_ITEM_BUILD_WORN_ICON, .proc/build_worn_cham)
			else
				RegisterSignal(A, COMSIG_ITEM_EQUIPPED, .proc/unmodify) //bulky objects can't be normally held anyway, and also lack inhands.
	prev_name = A.name
	A.name = disguise.name
	RegisterSignal(A, COMSIG_PARENT_PRE_EXAMINE, .proc/cham_examine)
	RegisterSignal(A, COMSIG_ATOM_GET_EXAMINE_NAME, .proc/cham_article)
	RegisterSignal(A, COMSIG_ATOM_REMOVED_FROM_HUD, .proc/unmodify)

/datum/component/chameleon/UnregisterFromParent()
	UnregisterSignal(parent, list(COMSIG_ATOM_EMP_ACT, COMSIG_ATOM_EX_ACT, COMSIG_OBJ_TAKE_DAMAGE, COMSIG_ITEM_ATTACK, COMSIG_ITEM_EQUIPPED, COMSIG_PARENT_PRE_EXAMINE, COMSIG_ATOM_REMOVED_FROM_HUD))

/datum/component/chameleon/Destroy()
	var/atom/movable/A = parent
	if(D?.hud && (A in D.hud.hudatoms))
		D.hud.remove_from_hud(A)
	STOP_PROCESSING(SSobj, src)
	if(!QDELETED(A) && end_visual)
		new end_visual (get_turf(A), appearance)
		A.name = prev_name
		if(ismob(A.loc))
			var/mob/living/M = A.loc
			if(M.is_holding(A))
				var/obj/item/I = A
				addtimer(M, /mob.proc/update_inv_hands), 2) //updating the mob's held items overlays soon.
	return ..()

/datum/component/chameleon/proc/unmodify_if_worn(datum/source, mob/equipper, slot)

/datum/component/chameleon/proc/unmodify()
	if(!QDELETED(src))
		qdel(src)

/datum/component/chameleon/proc/cham_examine(mob/source)
	if(!isobserver(source) && !HAS_TRAIT(source, TRAIT_SPECTACLES_VIEW))
		to_chat(source, description)
		return COMPONENT_STOP_EXAMINE

/datum/component/chameleon/proc/cham_article(datum/source, mob/M, list/overrides)
	if(!isobserver(source) && !HAS_TRAIT(source, TRAIT_SPECTACLES_VIEW))
		overrides[EXAMINE_POSITION_ARTICLE] = D.gender == PLURAL ? "some" : "a"
		return COMPONENT_EXNAME_CHANGED

/datum/component/chameleon/proc/build_worn_cham(datum/source, list/standing, state, default_layer, default_icon_file, isinhands, femaleuniform)
	if(!isinhands || !ismob(loc))
		return
	var/obj/item/I = parent
	var/mob/M = loc
	var/left_rights = M.get_held_index_of_item(I) % 2
	var/icon_file = left_rights ? disguise.lefthand_icon : disguise.righthand_icon
	var/list/worn_overlays = left_rights ? disguise.left_overlays : disguise.right_overlays
	var/hands_layer = disguise.worn_layer
	if(!hands_layer) //I wish this thing was more standarized...
		if(iscarbon(M))
			hands_layer = HANDS_LAYER
		else if(isdrone(M))
			hands_layer = DRONE_HANDS_LAYER
		else if(isdevil(M))
			hands_layer = DEVIL_HANDS_LAYER
		else if(isgorilla(M))
			hands_layer = GORILLA_HANDS_LAYER
		else if(isguardian(M))
			hands_layer = GUARDIAN_HANDS_LAYER
		else
			hands_layer = HANDS_LAYER
	var/mutable_appearence/MA = mutable_appearance(icon_file, disguise.worn_state, -hands_layer)
	if(length(overlays))
		MA.overlays.Add(worn_overlays)
	MA.alpha = disguise.worn_alpha
	MA.color = disguise.worn_color
	standing[1] = MA
	return COMPONENT_BUILT_ICON

/datum/component/chameleon/proc/disrupt_anim()
	if(anim_busy)
		return
	anim_busy = TRUE
	var/A1 = max(appearance.alpha - rand(30, 50), 0)
	var/A2 = appearance.alpha
	var/C1 = list(rgb(77,77,77), rgb(150,150,150), rgb(28,28,28), rgb(0,0,0))
	var/C2 = appearance.color
	if(appearance.override)
		appearance.override = FALSE
		addtimer(VARSET_CALLBACK(appearance, override, TRUE), 1)
		addtimer(VARSET_CALLBACK(appearance, override, FALSE), 2)
		addtimer(VARSET_CALLBACK(appearance, override, TRUE), 3)
	animate(appearance, alpha = A1, color = C1, time = 2)
	animate(appearance, alpha = A2, color = C2, time = 2)
	addtimer(VARSET_CALLBACK(src, anim_busy, FALSE), 8)

/datum/component/chameleon/proc/disrupt_ex_act(datum/source, severity, target)
	if(!anim_busy)
		INVOKE_ASYNC(src, .proc/disrupt_anim)
	recalculate_time_left(1.5 MINUTES * severity)

/datum/component/chameleon/proc/disrupt_emp(datum/source, severity)
	INVOKE_ASYNC(src, .proc/disrupt_anim)
	recalculate_time_left(2 MINUTES * severity)

/datum/component/chameleon/proc/disrupt_obj(datum/source, damage_amount, damage_type, damage_flag, attack_dir, armour_penetration)
	INVOKE_ASYNC(src, .proc/disrupt_anim)
	recalculate_time_left(3 SECONDS * damage_amount)

/datum/component/chameleon/proc/disrupt_item(datum/source, mob/living/target, mob/living/user)

/datum/component/chameleon/proc/recalculate_time_left(modifier)
	if(time_left = CHAMELEON_NO_EXPIRE)
		return
	expiration_date += modifier
	var/n_time_left = expiration_date - world.time
	if(n_time_left < 0)
		if(!QDELETED(src))
			qdel(src)
		return
	timer_id = addtimer(CALLBACK(src, .proc/unmodify) n_time_left, TIMER_UNIQUE|TIMER_OVERRIDE|TIMER_NO_HASH_WAIT|TIMER_STOPPABLE)

#undef CHAMELEON_NO_EXPIRE