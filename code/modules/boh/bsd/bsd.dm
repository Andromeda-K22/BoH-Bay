//DEFINES
#define ENERGY_PER_TILE 15000 //arbitrary number, really - used to calculate how much of the fuel rod will get used just on distance alone.

#define JUMP_RANGE_WARNING 3 //Some hallucinations and bad messages
#define JUMP_RANGE_BAD 6 //Lots of hallucinations and bad messages, physical effects begin
#define JUMP_RANGE_VERY_BAD 7 //Going into the warp without a Gellar Field.
//following defines are in deciseconds
#define MESSAGE_INTERVAL_MINOR 300
#define MESSAGE_INTERVAL_BAD 200
#define MESSAGE_INTERVAL_AWFUL 100
#define PHYSICAL_EFFECT_INTERVAL 200



/*
math is rod_quantity[reagent] * fuels[reagent] = total energy available in rod.
assuming 10,000 of a fuel in rod_quantities, the following numbers should be relatively accurate:
Deuterium = 200,000
Hydrogen = 200,000
Tritium = 250,000
Phoron = 300,000
Supermatter = 400,000

Energy cost is increased by a a function of the ship's mass and tiles moved, so, smaller ships use less fuel and produce less heat.

Said function is vessel_mass(M), distance(D), energy cost per tile(T), times drive inefficency (E)

(M+(D*T))(E)

So, mass plus distance times energy cost per tile, times the drive's inefficency.

NTSS Dagon for example, with a four tile jump:

(100,000 + (4*15000) / 0.80) = 200,000. Uses an entire deuterium fuel rod up neatly for a four tile jump.

A deuterium rod can manage a six tile jump before being used up completely.

*/
/obj/structure/BSD_placeholder
	name = "bluespace drive"
	icon = 'icons/boh/bsd.dmi'
	icon_state = "shield_gen"

/obj/structure/BSD_placeholder/heat_exchanger
	name = "bluespace drive heat exchanger"
	icon_state = "bsd_heat_exchanger2"
	pixel_y = 1

/obj/structure/BSD_fuelcore_placeholder
	name = "bluespace drive fuel core placeholder"
	icon = 'icons/boh/bsd_32x64.dmi'
	icon_state = "bsd_fuelcore"

/obj/structure/BSD_capacitor_placeholder
	name = "bluespace drive capacitor placeholder"
	icon = 'icons/boh/bsd_32x64.dmi'
	icon_state = "capacitor"

//GENERIC TYPES AND PROCS

/obj/machinery/bsd
	name = "generic bluespace drive part"
	desc = "Probably shouldn't see this - something's wrong here!"
	var/width = 1

/obj/machinery/bsd/proc/SetBounds()
	bound_width = width * world.icon_size
	bound_height = world.icon_size

//END GENERIC TYPES AND PROCS

//PRIMARY CORE CODE

/obj/machinery/bsd/core
	name = "bluespace core containment unit"
	desc = "An advanced, miniturized particle accelerator, plasma constricton matrix and control system all in one package. The shell of the unit is clearly human in make, while the bluespace core within appears deeply alien."
	var/obj/effect/overmap/visitable/ship/linked
	//slave objects
	var/obj/machinery/bsd/fuel_core/fuel_core
	var/obj/machinery/bsd/heat_radiator/radiator
	//bad messages, used during 'normal' microjumps.
	var/list/physical_messages_bad = list()
	var/list/mental_messages_bad = list()
	//very bad messages, used when pushing the BSD to the ABSOLUTE LIMIT of it's jump range.
	var/list/physical_messages_very_bad = list()
	var/list/mental_messages_very_bad = list()

/obj/machinery/bsd/core/proc/attempt_hook_up(obj/effect/overmap/visitable/ship/sector)
	if(!istype(sector))
		return
	if(sector.check_ownership(src))
		linked = sector
		return 1

/obj/machinery/bsd/core/proc/sync_linked()
	var/obj/effect/overmap/visitable/ship/sector = map_sectors["[z]"]
	if(!sector)
		return
	return attempt_hook_up_recursive(sector)

/obj/machinery/bsd/core/proc/attempt_hook_up_recursive(obj/effect/overmap/visitable/ship/sector)
	if(attempt_hook_up(sector))
		return sector
	for(var/obj/effect/overmap/visitable/ship/candidate in sector)
		if((. = .(candidate)))
			return

//FUEL CORE CODE

/obj/machinery/bsd/fuel_core
	name = "bluespace fuel containment core"
	desc = "A cylindrical device with a port for a rod of fusion fuel. When active, it converts the fuel to highly energized fusion plasma and forces it into the bluespace core."
	icon = 'icons/boh/bsd_32x64.dmi'
	icon_state = "bsd_fuelcore"

	var/obj/machinery/bsd/core/master
	var/obj/item/weapon/fuel_assembly/fuel_rod
	var/list/fuels = list("deuterium" = 20, "tritium" = 25, "hydrogen" = 20, "phoron" = 30, "supermatter" = 40) //The list of fuel reagents we use, and how good they are, in turn.

/obj/machinery/bsd/fuel_core/proc/get_available_rod_energy() //Returns the energy left in the rod.
	var/available_energy
	if(!fuel_rod)
		return //no fuel rod - don't bother.
	for(var/R in fuel_rod.rod_quantities)
		if(R in fuels)
			available_energy = fuel_rod.rod_quantities[R] * fuels[R]
	return available_energy

/obj/machinery/bsd/fuel_core/proc/get_fuel_remaining() //Returns a precentage of the rod's remaining fuel.
	if(!fuel_rod)
		return //no fuel rod - don't bother.
	var/fuel_amount
	for(var/R in fuel_rod.rod_quantities)
		if(R in fuels)
			fuel_amount = fuel_rod.rod_quantities[R]
	if(!fuel_amount)
		return 0 //No fuel.
	if(fuel_amount == fuel_rod.initial_amount)
		return 100 //Maximum fuel avaliable.
	else
		return (fuel_amount / 100)

/obj/machinery/bsd/fuel_core/proc/use_rod_energy(var/energy)
	if(!fuel_rod)
		return 0
	//First, get how much energy the fuel rod even has in it.
	var/avaliable_energy = get_available_rod_energy()
	if(avaliable_energy < energy) //Not enough energy in the rod!
		return 0
	//Now we figure out how much fuel to use.
	var/fuel_to_use
	for(var/R in fuel_rod.rod_quantities)
		if(R in fuels)
			fuel_to_use = energy / fuels[R]
			fuel_rod.rod_quantities[R] -= fuel_to_use

/obj/machinery/bsd/fuel_core/on_update_icon()
	overlays.Cut()
	if(fuel_rod)
		overlays += image('icons/boh/bsd_32x64.dmi', "fuelcover_loaded")
		var/fuel_left = get_fuel_remaining()
		if(fuel_left >= 100)
			overlays += image('icons/boh/bsd_32x64.dmi', "fuelcore_vents_good")
			return
		if(fuel_left < 75)
			overlays += image('icons/boh/bsd_32x64.dmi', "fuelcore_vents_caution")
			return
		if(fuel_left < 25)
			overlays += image('icons/boh/bsd_32x64.dmi', "fuelcore_vents_good")
			return

/obj/machinery/bsd/fuel_core/attackby(obj/item/O as obj, mob/user as mob)
	if(istype(O, /obj/item/weapon/fuel_assembly))
		if(!user.unEquip(O, src))
			return
		to_chat(user, SPAN_NOTICE("You begin to insert the fuel rod into [src]."))
		if(!do_after(user, 20, src))
			to_chat(user, SPAN_WARNING("You stop inserting the fuel rod."))
			return
		O.forceMove(src)
		fuel_rod = O
		update_icon()

//HEAT RADIATOR CODE

/obj/machinery/bsd/heat_radiator
	name = "bluespace core heat radiator"
	desc = "A massive assemblage of pipes and pumps to move the massive amounts of heat generated by the bluespace jumping process into a cooling system."
	var/obj/machinery/bsd/core/master

/obj/machinery/bsd/capacitor
	name = "bluespace plasma storage unit"
	desc = "A large magnetorestriction plasma confinement unit, used to store highly charged plasma for use in a bluespace core."
	icon = 'icons/boh/bsd_32x64.dmi'
	icon_state = "capacitor"

	var/obj/machinery/bsd/core/master
	var/energy = 0 //stored energy
	var/safe_energy = 50000
	var/warn_energy = 75000
	var/danger_energy = 100000

/obj/machinery/bsd/capacitor/on_update_icon()
	overlays.Cut()
	if(energy)
		if(energy >= danger_energy)
			overlays += image('icons/boh/bsd_32x64.dmi', "capstate_bad")
			return
		if(energy >= warn_energy)
			overlays += image('icons/boh/bsd_32x64.dmi', "capstate_warning")
			return
		if(energy >= safe_energy)
			overlays += image('icons/boh/bsd_32x64.dmi', "capstate_good")
			return