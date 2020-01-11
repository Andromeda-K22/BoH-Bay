#define WEAPON_STATUS_RECHARGING 1 //weapon recharging
#define WEAPON_STATUS_RELOADING 2 //weapon is chambering a round from internal magazine
#define WEAPON_STATUS_REQUIRES_RELOAD 3 //weapon requires manual reload.
#define WEAPON_STATUS_OFFLINE 4 //weapon is offline
#define WEAPON_STATUS_READY 5 //weapon is ready to fire
#define WEAPON_STATUS_FIRING 6 //weapon is firing

#define WEAPON_FIREMODE_SINGLE 7 //fires one round.
#define WEAPON_FIREMODE_SALVO 8 //fires rounds one after the other, cycles from magazine.

#define WEAPON_NOTIFY_NOTICE 10 //blue text, doublebeep.
#define WEAPON_NOTIFY_ERROR 11 //red text, buzz.
#define WEAPON_NOTIFY_GOOD 12 //green text, ping.
#define WEAPON_NOTIFY_CAUTION 13 //red text, beep.

/obj/machinery/shipweapons/shipweapons2
	icon = 'icons/boh/obj/structures&machinery/railgun.dmi'
	name = "shipweapontwo"
	desc = "You shouldn't see this. Someone messed up."

	var/obj/item/shipweapons/ammo/chambered //chambered munition, if only firing one at a time.

	var/chamber_sound = 'sound/effects/extout.ogg'
	var/firing_state //animation for firing

	var/accepted_ammo_type = /obj/item/shipweapons/ammo //accepted ammo type.

	var/cooldown = 1 SECOND //cooldown, functionally used in Fire()
	var/magazine_capacity = 0 //internal mag capacity
	var/chamber_delay = 4 SECONDS //delay between firing and loading another round.
	var/salvo_rounds = 0 //used in WEAPON_FIREMODE_SALVO to determine how many shots are fired.
	var/salvo_rounds_left = 0 //used in WEAPON_FIREMODE_SALVO
	var/caliber //if uses_caliber is true
	var/megajoules_stored //how many megajoules do we have stored up
	var/megajoule_capacity //how many megajoules can we store at once
	var/max_power_draw //how much power can we draw at once.
	var/efficency //how efficent is our charging?

	var/has_magazine = FALSE //do we have a magazine?
	var/automatic_reload = FALSE //requires manual cycling
	var/has_ammo_states = FALSE //icon state changes on ammo status
	var/chambering = FALSE //are we loading a round into the chamber right now?
	var/salvo_completed = FALSE //have we completed our salvo?
	var/uses_caliber = FALSE //something something avoids extra subtyping.
	var/requires_charging = FALSE //maybe used for weapons that have their power in the ammo or are conventional in nature, rather than electromagnetic and such.

	var/firemode = WEAPON_FIREMODE_SINGLE //weapon fire mode

	var/list/magazine = list() //internal magazine.

	var/chamber_name = "chamber" //name of chamber - used for non-gun sorts of weapons.
	var/magazine_name = "magazine" //name of magazine, used for non-gun sorts of weapons.
	var/munition_name = "round" //name of munitionn, used for non-gun sorts of weapons.


/obj/machinery/shipweapons/shipweapons2/Initialize()
	//by default, requires at LEAST one matter bin, one capacitor, and one SMES coil.
	.=..()
	add_parts()
	component_parts = list()


/obj/machinery/shipweapons/shipweapons2/proc/add_parts()
	if(requires_charging)
		component_parts += new /obj/item/weapon/stock_parts/smes_coil(src)
		component_parts += new /obj/item/weapon/stock_parts/capacitor(src)
	if(has_magazine)
		component_parts += new /obj/item/weapon/stock_parts/matter_bin(src)
	RefreshParts()
	return

/obj/machinery/shipweapons/shipweapons2/RefreshParts()
	megajoule_capacity = 0
	max_power_draw = 0
	efficency = 0
	magazine_capacity = 0
	for(var/obj/item/weapon/stock_parts/smes_coil/S in component_parts)
		megajoule_capacity += (S.ChargeCapacity / CELLRATE) / 1000000 //standard coil = 90mj capacity, may need nerfing.
		max_power_draw += S.IOCapacity / 2
	for(var/obj/item/weapon/stock_parts/capacitor/C in component_parts)
		efficency = C.rating * 0.65
	if(has_magazine)
		for(var/obj/item/weapon/stock_parts/matter_bin/M in component_parts)
			magazine_capacity += M.rating * 2
	efficency = Clamp(efficency, 0, 0.90) //never more than 90% efficent.



/obj/machinery/shipweapons/shipweapons2/Process()
	if(stat & (BROKEN|NOPOWER)) //we're broken, no charging for us.
		return

	if(chambered)
		Charging(FALSE)
	else
		Charging(TRUE)

/obj/machinery/shipweapons/shipweapons2/Charging(var/passive = TRUE) //completely redoing this as well to integrate things.
	if(stat & (BROKEN|NOPOWER)) //we're broken, no charging for us.
		return
	if(megajoules_stored >= megajoule_capacity)
		update_use_power(1)
		return //we're done charging.

	var/power_to_draw
	var/mj_to_add

	if(passive)
		power_to_draw = max_power_draw * 0.25 // if we're charging up passively, only draw at a quarter of our total possible amount to avoid serious power grid stress.
		active_power_usage = power_to_draw
		update_use_power(2)
		mj_to_add = (power_to_draw * CELLRATE) * efficency
		megajoules_stored += mj_to_add
		world << "DEBUG: inputting [mj_to_add] to storage, passive."
		megajoules_stored = Clamp(megajoules_stored, 0, megajoule_capacity)
	else
		power_to_draw = max_power_draw // if we're charging up actively, all bets are off.
		active_power_usage = power_to_draw
		update_use_power(2)
		mj_to_add = (power_to_draw * CELLRATE) * efficency
		megajoules_stored += mj_to_add
		world << "DEBUG: inputting [mj_to_add] to storage, active."
		megajoules_stored = Clamp(megajoules_stored, 0, megajoule_capacity)

/obj/machinery/shipweapons/shipweapons2/Fire(var/after_salvo) //completely redoing this
	if(stat & (BROKEN|NOPOWER)) //we're broken, no firing for us.
		return

	if(!target)
		notify("No target.", WEAPON_NOTIFY_ERROR)
		return

	if(shipid && !linkedcomputer)
		ConnectWeapons()
		return


	if(!chambered)
		notify("No [munition_name] in [chamber_name]. Unable to fire.", WEAPON_NOTIFY_ERROR)
		return

	if(firemode == WEAPON_FIREMODE_SALVO && salvo_completed)
		salvo_completed = FALSE
		return

	if(cooldown >= world.time)
		notify("Weapon cooldown in progress. Unable to fire. Waiting...", WEAPON_NOTIFY_CAUTION)
		var/time_to_wait = (world.time -= cooldown) + 0.1 SECONDS //Just so we don't prolong the firing process more than we must.
		sleep(time_to_wait)

	if(chambered.megajoule_cost > megajoules_stored)
		notify("Weapon capacitors insufficently charged.", WEAPON_NOTIFY_ERROR)
		if(firemode == WEAPON_FIREMODE_SALVO)
			salvo_completed = TRUE
			salvo_rounds_left = 0
		return

	else if(!firing)
		firing = TRUE
		UpdateStatus(WEAPON_STATUS_FIRING) //and now things get funky.
		switch(firemode)
			if(WEAPON_FIREMODE_SINGLE)
				UpdateStatus(WEAPON_STATUS_FIRING)
				handle_chambered(chambered, firemode)

			if(WEAPON_FIREMODE_SALVO)
				UpdateStatus(WEAPON_STATUS_FIRING)
				if(!salvo_rounds_left)
					salvo_rounds_left = salvo_rounds
					salvo_completed = FALSE
				handle_chambered(chambered, firemode)

/obj/machinery/shipweapons/shipweapons2/UpdateStatus(var/weapon_status)
	switch(weapon_status)
		if(WEAPON_STATUS_RECHARGING)
			status = "Weapon Recharging"
		if(WEAPON_STATUS_RELOADING)
			status = "Weapon Reloading"
		if(WEAPON_STATUS_REQUIRES_RELOAD)
			status = "Manual weapon reload required"
		if(WEAPON_STATUS_OFFLINE)
			status = "Weapon Offline"
		if(WEAPON_STATUS_READY)
			status = "Weapon Ready"
		if(WEAPON_STATUS_FIRING)
			status = "Weapon Firing"

/obj/machinery/shipweapons/shipweapons2/update_icon()
	return //not used for the moment

/obj/machinery/shipweapons/shipweapons2/examine(mob/user)
	..()
	if(chambered)
		to_chat(user, "<span class='notice'>There is a [munition_name] in the [chamber_name].</span>")
	if(has_magazine)
		if(magazine.len == 0)
			to_chat(user, "<span class='notice'>The [magazine_name] is empty..</span>")
		else
			to_chat(user, "<span class='notice'>There are [magazine.len] [munition_name]s in the magazine.</span>")
	if(automatic_reload)
		to_chat(user, "<span class='notice'>It has a combat autoloader module installed.</span>")
	switch(firemode)
		if(WEAPON_FIREMODE_SINGLE)
			to_chat(user, "<span class='notice'>The [src] is set to fire a single [munition_name] at once.</span>")
		if(WEAPON_FIREMODE_SALVO)
			to_chat(user, "<span class='notice'>The [src] is set to fire [salvo_rounds] [munition_name]s in a salvo.</span>")

/obj/machinery/shipweapons/shipweapons2/proc/cycle(var/salvo_firing = FALSE, var/manual = FALSE) //used when cycling rounds from internal mag to chamber, supports auto/nonautomatic reloading
	UpdateStatus(WEAPON_STATUS_RELOADING)
	if(automatic_reload)
		if(chambered)
			notify("[capitalize(chamber_name)] full.", WEAPON_NOTIFY_ERROR)
			return

		if(!has_magazine)
			notify("Manual reload required.", WEAPON_NOTIFY_NOTICE)
			UpdateStatus(WEAPON_STATUS_REQUIRES_RELOAD)
			return

		if(!salvo_firing)
			notify("Attempting to cycle [munition_name] from [magazine_name] into [chamber_name].", WEAPON_NOTIFY_NOTICE)
			chamber(1)

		if(salvo_firing)
			notify("Cycling [munition_name].", WEAPON_NOTIFY_NOTICE)
			chamber(1, FALSE, TRUE)

	if(manual)
		if(chambered)
			notify("[capitalize(chamber_name)] full.", WEAPON_NOTIFY_ERROR)
			return
		chamber(1, TRUE)

/obj/machinery/shipweapons/shipweapons2/proc/chamber(var/chamber_amount = 0, var/manual = FALSE, var/after_salvo) //used when chambering round(s) from internal mag to chamber.
	var/total_chamber_delay = chamber_delay
	if(chambering)
		return
	//check if we have enough ammo in the magazine, first! Continue normally, if so.
	if(magazine.len == 0)
		if(salvo_rounds_left)
			notify("Salvo interrupted - [magazine_name] empty.", WEAPON_NOTIFY_ERROR)
			salvo_rounds_left = 0
			return
		notify("[capitalize(magazine_name)] empty!", WEAPON_NOTIFY_ERROR)
		return
	chambering = TRUE
	if(chambered)
		notify("[capitalize(chamber_name)] full!", WEAPON_NOTIFY_ERROR)
		chambering = FALSE
		return
	if(after_salvo)
		total_chamber_delay = chamber_delay / 2 //loading rounds is faster, if doing salvo fire.
	spawn(total_chamber_delay)
		for(var/obj/item/shipweapons/ammo/C in contents)
			chambered = next_in_list(C, magazine)
			magazine -= next_in_list(C, magazine)
			playsound(src, chamber_sound, 40, 1)
			notify("[capitalize(munition_name)] cycled into [chamber_name] from internal [magazine_name].", WEAPON_NOTIFY_GOOD)
			chambering = FALSE
			break //only want to do it once

/obj/machinery/shipweapons/shipweapons2/proc/handle_firing(var/hull_damage = 0, var/shield_damage = 0, var/shield_pen_chance = 0, var/module_damage_chance = 0) //called in Fire()
	return

/obj/machinery/shipweapons/shipweapons2/proc/handle_chambered(var/obj/item/shipweapons/ammo/AM, var/firemode = 0)
	notify("Weapon firing.", WEAPON_NOTIFY_CAUTION)
	sleep(5)
	playsound(src, fire_sound, 40, 1)
	flick(firing_state, src)
	handle_firing(AM.hull_damage, AM.shield_damage, AM.shield_pen_chance, AM.module_damage_chance)
	cooldown = world.time += AM.cooldown
	if(chambered.megajoule_cost)
		megajoules_stored -= chambered.megajoule_cost
	var/chambered_wait = AM.cooldown
	for(var/mob/M in viewers(5, src))
		shake_camera(M, AM.camera_shake_amount, 1)
	sleep(2)
	if(AM.consumed)
		QDEL_NULL(AM)
		chambered = null
	else
		AM.depleted = TRUE
		chambered = null
		if(AM.has_spent_type)
			eject(AM, TRUE)
		else
			eject(AM)
	if(firemode == WEAPON_FIREMODE_SALVO)
		cycle(TRUE, FALSE)
		salvo_rounds_left -= 1
	if(firemode != WEAPON_FIREMODE_SALVO)
		cycle(FALSE, FALSE)
	firing = FALSE
	if(firemode == WEAPON_FIREMODE_SALVO)
		if(salvo_rounds_left != 0)
			addtimer(CALLBACK(src, .proc/Fire, TRUE), chambered_wait += 0.1 SECONDS)
		else
			notify("Salvo completed.", WEAPON_NOTIFY_GOOD)
			salvo_completed = TRUE
			salvo_rounds_left = 0

/obj/machinery/shipweapons/shipweapons2/proc/try_load(var/mob/user, var/obj/item/shipweapons/ammo/ammo)
	if(ammo.depleted)
		to_chat(user, "<span class='warning'>A depleted round isn't particularly useful.</span>")
		return

	if(uses_caliber && (ammo.caliber != caliber))
		to_chat(user, "<span class='danger'>This isn't the right ammo for this weapon!</span>")
		return

	if(!uses_caliber && !istype(ammo, accepted_ammo_type))
		to_chat(user, "<span class='danger'>This isn't the right ammo for this weapon!</span>")
		return

	if(!has_magazine)
		if(chambered)
			to_chat(user, "<span class='danger'>The chamber is full.</span>")
			return
		playsound(src, chamber_sound, 40, 1)
		visible_message("<span class='notice'>[user] attempts to load [src]'s chamber.</span>")
		if(do_after(user, 30))
			if(chambered)
				to_chat(user, "<span class='danger'>The chamber is full.</span>")
				return
			ammo.forceMove(src)
			ammo.parentweapon = src
			chambered = ammo
			visible_message("<span class='notice'>[user] loads [ammo] into [src]'s chamber.</span>")
			notify("Round loaded into chamber.", WEAPON_NOTIFY_GOOD, TRUE)
		else
			visible_message("<span class='notice'>[user] stops loading [src]'s chamber.</span>")
			return
	else
		if(magazine.len == magazine_capacity)
			to_chat(user, "<span class='danger'>The magazine is full.</span>")
			return
		playsound(src, chamber_sound, 40, 1)
		visible_message("<span class='notice'>[user] attempts to load [src]'s magazine..</span>")
		if(do_after(user, 30))
			if(magazine.len == magazine_capacity)
				to_chat(user, "<span class='danger'>The magazine is full.</span>")
				return
			ammo.forceMove(src)
			magazine += ammo
			ammo.parentweapon = src
			visible_message("<span class='notice'>[user] loads [ammo] into [src]'s magazine.</span>")
			notify("Round loaded into magazine.", WEAPON_NOTIFY_GOOD, TRUE)
		else
			visible_message("<span class='notice'>[user] stops loading [src]'s magazine.</span>")
			return

/obj/machinery/shipweapons/shipweapons2/proc/eject(var/obj/item/shipweapons/ammo/ammo, var/spent = 0, var/chambered = FALSE, var/magazine = FALSE)
	if(spent)
		var/obj/item/shipweapons/ammo/M = new ammo.spent_type(get_turf(src))
		M.depleted = TRUE //sanity check, just in case someone makes a mistake.
		visible_message("<span class='danger'>[src] ejects [ammo.name]!</span>")
		notify("Spent [munition_name] ejected.", WEAPON_NOTIFY_NOTICE)
		qdel(ammo)
		return
	if(chambered)
		chambered = null
	if(magazine)
		magazine -= ammo
	visible_message("<span class='danger'>[src] ejects [ammo.name]!</span>")
	ammo.forceMove(get_turf(src))
	notify("[capitalize(munition_name)] ejected.", WEAPON_NOTIFY_NOTICE)
	playsound(src, chamber_sound, 40, 1)

/obj/machinery/shipweapons/shipweapons2/proc/notify(var/text, var/type, var/silent = FALSE)
	sleep(5) //a little delay.
	var/class
	var/sound
	var/color
	var/veerb //supposed to be verb but uuuh yeah
	switch(type)
		if(WEAPON_NOTIFY_NOTICE)
			class = "notice"
			sound = 'sound/machines/chime.ogg'
			color = "#0761b0"
			veerb = "states"
		if(WEAPON_NOTIFY_ERROR)
			class = "warning"
			sound = 'sound/machines/buzz-two.ogg'
			color = "#d10000"
			veerb = "buzzes"
		if(WEAPON_NOTIFY_GOOD)
			class = "good"
			sound = 'sound/machines/ping.ogg'
			color = "#0ad100"
			veerb = "chimes"
		if(WEAPON_NOTIFY_CAUTION)
			class = "bad"
			sound = 'sound/machines/twobeep.ogg'
			color = "#fcba03"
			veerb = "beeps"

	for(var/mob/O in hearers(src, null))
		O.show_message("\icon[src] <span class = '[class]'>[src] [veerb], '[text]'</span>", 2)
	if(!silent)
		playsound(src.loc, sound, 50, 0)
	blink(color)

/obj/machinery/shipweapons/shipweapons2/proc/blink(var/color)
	set_light(1, 2, 8, 2, color)
	sleep(10)
	set_light(0, 0, 0, 2, "#ffffff")

/obj/machinery/shipweapons/shipweapons2/attack_hand(var/mob/user)
	visible_message("<span class='notice'>[user] engages the [src]'s cycling mechanism.</span>")
	to_chat(user, "<span class='notice'>Cycling [src]. This will take [chamber_delay / 10] seconds.</span>")
	cycle(FALSE, TRUE)

/obj/item/shipweapons/ammo
	icon = 'icons/boh/munitions.dmi'
	name = "shipweapontwoammo"
	desc = "You shouldn't see this. Someone messed up."

	var/engraved //text, if we've been engraved. People do this in real life with cannon rounds, so why not.

	var/obj/machinery/shipweapons/shipweapons2/parentweapon //our parent weapon, just in case we need this for ... some reason.
	var/spent_type //if we have a different spent ammo type.

	var/shield_damage = 0 //how much shield damage do we do
	var/hull_damage = 0 //how much hull damage we do
	var/shield_pen_chance = 0 //chance of penetrating shields
	var/module_damage_chance = 0 //chance of damaging modules
	var/cooldown = 1 SECOND //how long does firing us make our parent weapon cool down?
	var/camera_shake_amount = 0 //how much do we shake the camera when fired?
	var/load_delay = 3 SECONDS //how long do we take to load into a weapons chamber/magazine?
	var/caliber //caliber, if uses_caliber is true
	var/megajoule_cost = 5 //how many megajoules are needed to fire us
	var/heat_increase //if we don't use power, we still heat up the gun, probably.

	var/consumed = FALSE //are we deleted after firing? maybe used for some kind of canister based weapon later on.
	var/has_spent_type = FALSE //do we have a spent type to be used in eject()?
	var/depleted = FALSE //if not consumed, are we depleted?
	var/camera_shake = FALSE //Do we make the camera shake when we're fired?
	var/volatile = FALSE //if true, when ex_act'd, bad things happen.
	var/engravable = FALSE //some things you shouldn't engrave.
	var/is_missile = FALSE //if we're missiles we don't care about heat increase.

	var/list/special_effects = list() //Do we do anything special? Reserved for future use.
	var/list/volatile_boom = list(1, 1, 1, 1) //size of the explosion, if volatile is TRUE and the munition has ex_act called on it.

/obj/item/shipweapons/ammo/MouseDrop(over_object, src_location, over_location)
	if(istype(over_object, /obj/machinery/shipweapons/shipweapons2))
		var/obj/machinery/shipweapons/shipweapons2/W = over_object
		W.try_load(usr, src)
		return

/obj/item/shipweapons/ammo/examine(mob/user)
	..()
	if(caliber)
		to_chat(user, "<span class='notice'>Eyeballing it, you'd say this round is [caliber]mm.</span>")
	if(volatile)
		to_chat(user, "<span class='danger'>There is a warning label reading, 'DANGER: VOLATILE!' on the casing.</span>")
	if(engraved)
		to_chat(user, "<span class='notice'>It's engraved with '[engraved]' on the casing.</span>")

/obj/machinery/shipweapons/shipweapons2/railgun
	name = "Railgun"
	desc = "The Hephaestus Industries XCM-HAVOK is a 155mm ship-to-ship combat weapon intended to fire metal sabots from an internal magazine. Extremely dangerous, extremely expensive."
	icon_state = "Railgun"
	firing_state = "Railgun_firing"
	has_magazine = TRUE
	accepted_ammo_type = /obj/item/shipweapons/ammo/railgun_sabot
	fire_sound = 'sound/machines/shipweapons2/railgun_fire.ogg'
	chamber_sound = 'sound/machines/shipweapons2/mac_load.ogg'
	automatic_reload = TRUE
	firemode = WEAPON_FIREMODE_SALVO
	salvo_rounds = 5
	requires_charging = TRUE

/obj/machinery/shipweapons/shipweapons2/railgun/add_parts()
	component_parts += new /obj/item/weapon/stock_parts/capacitor(src)
	component_parts += new /obj/item/weapon/stock_parts/matter_bin(src)
	component_parts += new /obj/item/weapon/stock_parts/matter_bin(src)
	component_parts += new /obj/item/weapon/stock_parts/matter_bin(src)
	RefreshParts()

/obj/item/shipweapons/ammo/railgun_sabot
	name = "railgun sabot"
	desc = "A hunk of metal intended to go inside of a railgun. Velocitas Eradico."
	icon_state = "railgun_ammo"
	hull_damage = 75
	shield_damage = 200
	module_damage_chance = 20
	cooldown = 5 SECONDS
	consumed = TRUE
	camera_shake = TRUE
	camera_shake_amount = 3
	engravable = TRUE
	megajoule_cost = 87 //155 mm projectile, assuming 28kg weight @ 2.5 km/s = 87 mj of kinetic energy.



