GLOBAL_LIST_EMPTY(active_alternate_appearances)


/atom
	var/list/alternate_appearances

/atom/proc/remove_alt_appearance(key)
	if(alternate_appearances)
		for(var/K in alternate_appearances)
			var/datum/atom_hud/alternate_appearance/AA = alternate_appearances[K]
			if(AA.appearance_key == key)
				AA.remove_from_hud(src)
				break

/atom/proc/add_alt_appearance(type, key, ...)
	if(!type || !key)
		return
	if(alternate_appearances && alternate_appearances[key])
		return
	var/list/arguments = args.Copy(2)
	new type(arglist(arguments))

/datum/atom_hud/alternate_appearance
	var/appearance_key

/datum/atom_hud/alternate_appearance/New(key)
	..()
	GLOB.active_alternate_appearances += src
	appearance_key = key || appearance_key
	hud_icons += appearance_key

/datum/atom_hud/alternate_appearance/Destroy()
	GLOB.active_alternate_appearances -= src
	return ..()

/datum/atom_hud/alternate_appearance/proc/onNewMob(mob/M)
	if(mobShouldSee(M))
		add_hud_to(M)

/datum/atom_hud/alternate_appearance/proc/mobShouldSee(mob/M)
	return FALSE

/datum/atom_hud/alternate_appearance/add_to_hud(atom/A, image/I)
	. = ..()
	if(.)
		LAZYINITLIST(A.alternate_appearances)
		A.alternate_appearances[appearance_key] = src

/datum/atom_hud/alternate_appearance/remove_from_hud(atom/A, sync = TRUE)
	. = ..()
	if(.)
		LAZYREMOVE(A.alternate_appearances, appearance_key)
		A.hud_list -= appearance_key


//an alternate appearance that attaches a single image to a single atom
/datum/atom_hud/alternate_appearance/basic
	var/atom/target
	var/image/theImage
	var/add_ghost_version = FALSE
	var/ghost_appearance

/datum/atom_hud/alternate_appearance/basic/New(key, image/I, target_sees_appearance = TRUE)
	..()
	theImage = I
	target = I.loc
	add_to_hud(target, I)
	if(target_sees_appearance && ismob(target))
		add_hud_to(target)
	if(add_ghost_version)
		var/image/ghost_image = image(icon = I.icon , icon_state = I.icon_state, loc = I.loc)
		ghost_image.override = FALSE
		ghost_image.alpha = 128
		ghost_appearance = new /datum/atom_hud/alternate_appearance/basic/observers(key + "_observer", ghost_image, FALSE)

/datum/atom_hud/alternate_appearance/basic/Destroy()
	. = ..()
	if(ghost_appearance)
		QDEL_NULL(ghost_appearance)

/datum/atom_hud/alternate_appearance/basic/add_to_hud(atom/A)
	LAZYINITLIST(A.hud_list)
	A.hud_list[appearance_key] = theImage
	. = ..()

/datum/atom_hud/alternate_appearance/basic/remove_from_hud(atom/A, sync = TRUE)
	. = ..()
	if(. && !QDELETED(src))
		qdel(src)

/datum/atom_hud/alternate_appearance/basic/everyone
	add_ghost_version = TRUE

/datum/atom_hud/alternate_appearance/basic/everyone/New()
	..()
	for(var/mob in GLOB.mob_list)
		if(mobShouldSee(mob))
			add_hud_to(mob)

/datum/atom_hud/alternate_appearance/basic/everyone/mobShouldSee(mob/M)
	return !isobserver(M)

/datum/atom_hud/alternate_appearance/basic/silicons

/datum/atom_hud/alternate_appearance/basic/silicons/New()
	..()
	for(var/mob in GLOB.silicon_mobs)
		if(mobShouldSee(mob))
			add_hud_to(mob)

/datum/atom_hud/alternate_appearance/basic/silicons/mobShouldSee(mob/M)
	if(issilicon(M))
		return TRUE
	return FALSE

/datum/atom_hud/alternate_appearance/basic/observers
	add_ghost_version = FALSE //just in case, to prevent infinite loops

/datum/atom_hud/alternate_appearance/basic/observers/New()
	..()
	for(var/mob in GLOB.dead_mob_list)
		if(mobShouldSee(mob))
			add_hud_to(mob)

/datum/atom_hud/alternate_appearance/basic/observers/mobShouldSee(mob/M)
	return isobserver(M)

/datum/atom_hud/alternate_appearance/basic/noncult

/datum/atom_hud/alternate_appearance/basic/noncult/New()
	..()
	for(var/mob in GLOB.player_list)
		if(mobShouldSee(mob))
			add_hud_to(mob)

/datum/atom_hud/alternate_appearance/basic/noncult/mobShouldSee(mob/M)
	if(!iscultist(M))
		return TRUE
	return FALSE

/datum/atom_hud/alternate_appearance/basic/cult

/datum/atom_hud/alternate_appearance/basic/cult/New()
	..()
	for(var/mob in GLOB.player_list)
		if(mobShouldSee(mob))
			add_hud_to(mob)

/datum/atom_hud/alternate_appearance/basic/cult/mobShouldSee(mob/M)
	if(iscultist(M))
		return TRUE
	return FALSE

/datum/atom_hud/alternate_appearance/basic/blessedAware

/datum/atom_hud/alternate_appearance/basic/blessedAware/New()
	..()
	for(var/mob in GLOB.mob_list)
		if(mobShouldSee(mob))
			add_hud_to(mob)

/datum/atom_hud/alternate_appearance/basic/blessedAware/mobShouldSee(mob/M)
	if(M.mind && (M.mind.assigned_role == "Chaplain"))
		return TRUE
	if (istype(M, /mob/living/simple_animal/hostile/construct/wraith))
		return TRUE
	if(isrevenant(M) || iseminence(M) || iswizard(M))
		return TRUE
	return FALSE

datum/atom_hud/alternate_appearance/basic/onePerson
	var/mob/seer

/datum/atom_hud/alternate_appearance/basic/onePerson/mobShouldSee(mob/M)
	if(M == seer)
		return TRUE
	return FALSE

/datum/atom_hud/alternate_appearance/basic/onePerson/New(key, image/I, mob/living/M)
	..(key, I, FALSE)
	seer = M
	add_hud_to(seer)


/datum/atom_hud/alternate_appearance/shared
	var/list/image/appearances = list() //we can't use hud_icons for these, lest we apply all the cached appearances on every target.
	var/override_appearance = FALSE //wheter the appearance overrides the mob's appearance or not.
	var/alpha_multiplier = 1 //multiplier (0 - 1), not RGB (0 - 255).
	var/datum/atom_hud/alternate_appearance/shared/alt_appearance //purposely similar to /basic's ghost_appearance.
	var/alt_appearance_type //the above's type created on New(), must be /shared.

/datum/atom_hud/alternate_appearance/shared/New(key)
	..()
	if(alt_appearance_type)
		alt_appearance = new alt_appearance_type(key ? "[key]_alt" : null)

/datum/atom_hud/alternate_appearance/shared/proc/register_appearance(atom/A, id, create_copy = TRUE)
	if(!A)
		return
	var/disguise = id || A //shouldn't be a number, really
	if(alt_appearance)
		INVOKE_ASYNC(alt_appearance, .proc/register_appearance, A, disguise, TRUE) //create_copy = TRUE, we are not going to use the same atom here.
	var/atom/I
	if(create_copy)
		I = image(A.icon, A.icon_state, A.layer)
		I.copy_overlays(A)
	else
		I = A // mostly for mutable_appearances/images
	I.override = override_appearance
	I.alpha = CLAMP(round(A.alpha * alpha_multiplier), 0, 255)
	appearances[disguise] = I
	return I

/datum/atom_hud/alternate_appearance/shared/add_to_hud(atom/A, disguise, ...)
	if(!A || (A.alternate_appearances && A.alternate_appearances[appearance_key]))
		return FALSE
	var/image/C = appearances[disguise]
	if(!C)
		return
	var/image/I = image(loc = A)
	I.appearance = C
	LAZYSET(A.hud_list, appearance_key, I)
	if(alt_appearance)
		var/list/arguments = list(alt_appearance, /datum/atom_hud.proc/add_to_hud)
		arguments += args.Copy(3)
		INVOKE_ASYNC(arglist(arguments))
	. = ..() //our return value differs from the parent, should be set.
	hudatoms[A] = disguise // Yes, we are using hudatoms as an associative list.

/datum/atom_hud/alternate_appearance/shared/proc/unregister_appearance(disguise)
	var/image/I = appearances[disguise]
	if(I)
		qdel(I)
	appearances -= disguise
	for(var/A in hudatoms)
		if(hudatoms[A] == disguise)
			remove_from_hud(A, FALSE)
	if(alt_appearance)
		INVOKE_ASYNC(alt_appearance, .proc/unregister_appearance, disguise)

/datum/atom_hud/alternate_appearance/shared/remove_from_hud(atom/A, sync = TRUE)
	. = ..()
	if(!.)
		return
	if(sync && alt_appearance)
		INVOKE_ASYNC(alt_appearance, /datum/atom_hud.proc/remove_from_hud, A)


//alternate_appearance / component hybrid frankenstein. The other half can be found in components/chameleon.dm.
/datum/atom_hud/alternate_appearance/shared/chameleon
	appearance_key = CHAMELEON_HUD
	var/use_alt_holo_mask = FALSE
	alt_appearance_type = /datum/atom_hud/alternate_appearance/shared/chameleon/spectacles_view

/datum/atom_hud/alternate_appearance/shared/chameleon/mobShouldSee(mob/M)
	if(!isobserver(M) && !HAS_TRAIT(M, TRAIT_SPECTACLES_VIEW))
		return TRUE

/datum/atom_hud/alternate_appearance/shared/chameleon/add_to_hud(atom/A, disguise, image/mask, image/alt_mask)
	. = ..()
	if(!.)
		return
	var/image/M = use_alt_holo_mask ? alt_mask : mask
	if(M)
		apply_mask(. , M)

#if DM_VERSION >= 513

/datum/atom_hud/alternate_appearance/shared/chameleon/proc/apply_mask(image/I, image/M)
	target_rs = M.generate_render_target()
	I.filters += filter(type = "alpha", render_source = target_rs)
	return M

#else

/datum/atom_hud/alternate_appearance/shared/chameleon/proc/apply_mask()
	return

#endif

/datum/atom_hud/alternate_appearance/shared/chameleon/spectacles_view
	appearance_key = CHAM_SPECTACLES_HUD
	override_appearance = FALSE
	alpha_multiplier = 0.5
	use_alt_holo_mask = TRUE

/datum/atom_hud/alternate_appearance/shared/chameleon/spectacles_view/mobShouldSee(mob/M)
	if(!(..())) //we see what they can't, and viceversa.
		return TRUE

/obj/item/chameleondisguiser
	var/list/datum/chameleon_appearance/all_disguises //contains the current diguises.
	var/static/cham_id = 0
	var/cham_limit = 12
	var/slot_limit = 8

/obj/item/chameleondisguiser/proc/add_appearance(obj/O)
	if(LAZYLEN(all_disguises) >= slot_limit)
		//warning message about hardware limitations here
		return
	var/datum/chameleon_appearance/CA = new(O, null, 20 MINUTES, "disguise_glitch", "scanline")
	RegisterSignal(CA, COMSIG_PARENT_PREQDELETED, .proc/clear_from_list)
	LAZYADD(all_disguises, CA)

/obj/item/chameleondisguiser/proc/clear_from_list(datum/chameleon_appearance/source)
	LAZYREMOVE(all_disguises, source)

/obj/item/chameleondisguiser/proc/apply_appearance(obj/O, datum/chameleon_appearance/CA)
	var/num_cham = 0
	for(var/A in all_disguises)
		var/datum/chameleon_appearance/D = A
		num_cham += LAZYLEN(D.active_components)
		if(num_cham >= cham_limit)
			//warning message about hardware limitations here
			return
	O.AddComponent(/datum/component/chameleon, CA)

/obj/item/chameleondisguiser/proc/remove_appearance(datum/component/chameleon/C, datum/chameleon_appearance/CA)
	if(!(C.cham in all_disguises))
		//warning message hinting incompatible holographic appearance of different source.
		return
	qdel(C)
