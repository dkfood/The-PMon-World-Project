#===============================================================================
# NOTE: In Gen 7+, the Day Care is replaced by the Pokémon Nursery, which works
#       in much the same way except deposited Pokémon no longer gain Exp because
#       of the player walking around and, in Gen 8+, deposited Pokémon are able
#       to learn egg moves from each other if they are the same species. In
#       Essentials, this code can be used for both facilities, and these
#       mechanics differences are set by some Settings.
# NOTE: The Day Care has a different price than the Pokémon Nursery. For the Day
#       Care, you are charged when you withdraw a deposited Pokémon and you pay
#       an amount based on how many levels it gained. For the Nursery, you pay
#       $500 up-front when you deposit a Pokémon. This difference will appear in
#       the Day Care Lady's event, not in these scripts.
#===============================================================================
class DayCare
  #=============================================================================
  # Code that generates an egg based on two given Pokémon.
  #=============================================================================
  module EggGenerator
    module_function

    def generate(mother, father)
      # Determine which Pokémon is the mother and which is the father
      # Ensure mother is female, if the pair contains a female
      # Ensure father is male, if the pair contains a male
      # Ensure father is genderless, if the pair is a genderless with Ditto
      if mother.male? || father.female? || mother.genderless?
        mother, father = father, mother
      end
      mother_data = [mother, mother.species_data.egg_groups.include?(:Ditto)]
      father_data = [father, father.species_data.egg_groups.include?(:Ditto)]
      # Determine which parent the egg's species is based from
      species_parent = (mother_data[1]) ? father : mother
      # Determine the egg's species
      baby_species = determine_egg_species(species_parent.species, mother, father)
      mother_data.push(mother.species_data.breeding_can_produce?(baby_species))
      father_data.push(father.species_data.breeding_can_produce?(baby_species))
      # Generate egg
      egg = generate_basic_egg(baby_species)
      # Inherit properties from parent(s)
      inherit_form(egg, species_parent, mother_data, father_data)
      inherit_nature(egg, mother, father)
      inherit_ability(egg, mother_data, father_data)
      inherit_moves(egg, mother_data, father_data)
      inherit_IVs(egg, mother, father)
      inherit_poke_ball(egg, mother_data, father_data)
      # Calculate other properties of the egg
      set_shininess(egg, mother, father)   # Masuda method and Shiny Charm
      set_pokerus(egg)
      # Recalculate egg's stats
      egg.calc_stats
      return egg
    end

    def determine_egg_species(parent_species, mother, father)
      ret = GameData::Species.get(parent_species).get_baby_species(true, mother.item_id, father.item_id)
      # Check for alternate offspring (i.e. Nidoran M/F, Volbeat/Illumise, Manaphy/Phione)
      offspring = GameData::Species.get(ret).offspring
      ret = offspring.sample if offspring.length > 0
      return ret
    end

    def generate_basic_egg(species)
      egg = Pokemon.new(species, Settings::EGG_LEVEL)
      egg.name           = _INTL("Egg")
      egg.steps_to_hatch = egg.species_data.hatch_steps
      egg.obtain_text    = _INTL("Day-Care Couple")
      egg.happiness      = 120
      egg.form           = 0 if species == :SINISTEA
      # Set regional form
      new_form = MultipleForms.call("getFormOnEggCreation", egg)
      egg.form = new_form if new_form
      return egg
    end

    def inherit_form(egg, species_parent, mother, father)
      # mother = [mother, mother_ditto, mother_in_family]
      # father = [father, father_ditto, father_in_family]
      # Inherit form from the parent that determined the egg's species
      if species_parent.species_data.has_flag?("InheritFormFromMother")
        egg.form = species_parent.form
      end
      # Inherit form from a parent holding an Ever Stone
      [mother, father].each do |parent|
        next if !parent[2]   # Parent isn't a related species to the egg
        next if !parent[0].species_data.has_flag?("InheritFormWithEverStone")
        next if !parent[0].hasItem?(:EVERSTONE)
        egg.form = parent[0].form
        break
      end
    end

    def get_moves_to_inherit(egg, mother, father)
      # mother = [mother, mother_ditto, mother_in_family]
      # father = [father, father_ditto, father_in_family]
      move_father = (father[1]) ? mother[0] : father[0]
      move_mother = (father[1]) ? father[0] : mother[0]
      moves = []
      # Get level-up moves known by both parents
      egg.getMoveList.each do |move|
        next if move[0] <= egg.level   # Could already know this move by default
        next if !mother[0].hasMove?(move[1]) || !father[0].hasMove?(move[1])
        moves.push(move[1])
      end
      # Inherit Machine moves from father (or non-Ditto genderless parent)
      if Settings::BREEDING_CAN_INHERIT_MACHINE_MOVES && !move_father.female?
        GameData::Item.each do |i|
          move = i.move
          next if !move
          next if !move_father.hasMove?(move) || !egg.compatible_with_move?(move)
          moves.push(move)
        end
      end
      # Inherit egg moves from each parent
      if !move_father.female?
        egg.species_data.egg_moves.each do |move|
          moves.push(move) if move_father.hasMove?(move)
        end
      end
      if Settings::BREEDING_CAN_INHERIT_EGG_MOVES_FROM_MOTHER && move_mother.female?
        egg.species_data.egg_moves.each do |move|
          moves.push(move) if move_mother.hasMove?(move)
        end
      end
      # Learn Volt Tackle if a parent has a Light Ball and is in the Pichu family
      if egg.species == :PICHU && GameData::Move.exists?(:VOLTTACKLE) &&
         ((father[2] && father[0].hasItem?(:LIGHTBALL)) ||
          (mother[2] && mother[0].hasItem?(:LIGHTBALL)))
        moves.push(:VOLTTACKLE)
      end
      return moves
    end

    def inherit_moves(egg, mother, father)
      moves = get_moves_to_inherit(egg, mother, father)
      # Remove duplicates (keeping the latest ones)
      moves = moves.reverse
      moves |= []   # remove duplicates
      moves = moves.reverse
      # Learn moves
      first_move_index = moves.length - Pokemon::MAX_MOVES
      first_move_index = 0 if first_move_index < 0
      (first_move_index...moves.length).each { |i| egg.learn_move(moves[i]) }
    end

    def inherit_nature(egg, mother, father)
      new_natures = []
      new_natures.push(mother.nature) if mother.hasItem?(:EVERSTONE)
      new_natures.push(father.nature) if father.hasItem?(:EVERSTONE)
      return if new_natures.empty?
      egg.nature = new_natures.sample
    end

    # The female parent (or the non-Ditto parent) can pass down its Hidden
    # Ability (60% chance) or its regular ability (80% chance).
    # NOTE: This is how ability inheritance works in Gen 6+. Gen 5 is more
    #       restrictive, and even works differently between BW and B2W2, and I
    #       don't think that is worth adding in. Gen 4 and lower don't have
    #       ability inheritance at all, and again, I'm not bothering to add that
    #       in.
    def inherit_ability(egg, mother, father)
      # mother = [mother, mother_ditto, mother_in_family]
      # father = [father, father_ditto, father_in_family]
      parent = (mother[1]) ? father[0] : mother[0]   # The female or non-Ditto parent
      if parent.hasHiddenAbility?
        egg.ability_index = parent.ability_index if rand(100) < 60
      elsif rand(100) < 80
        egg.ability_index = parent.ability_index
      else
        egg.ability_index = (parent.ability_index + 1) % 2
      end
    end

    def inherit_IVs(egg, mother, father)
      # Get all stats
      stats = []
      GameData::Stat.each_main { |s| stats.push(s.id) }
      # Get the number of stats to inherit (includes ones inherited via Power items)
      inherit_count = 3
      if Settings::MECHANICS_GENERATION >= 6
        inherit_count = 5 if mother.hasItem?(:DESTINYKNOT) || father.hasItem?(:DESTINYKNOT)
      end
      # Inherit IV because of Power items (if both parents have the same Power
      # item, then the parent that passes that Power item's stat down is chosen
      # randomly)
      power_items = [
        [:POWERWEIGHT, :HP],
        [:POWERBRACER, :ATTACK],
        [:POWERBELT,   :DEFENSE],
        [:POWERLENS,   :SPECIAL_ATTACK],
        [:POWERBAND,   :SPECIAL_DEFENSE],
        [:POWERANKLET, :SPEED]
      ]
      power_stats = {}
      [mother, father].each do |parent|
        power_items.each do |item|
          next if !parent.hasItem?(item[0])
          power_stats[item[1]] ||= []
          power_stats[item[1]].push(parent.iv[item[1]])
          break
        end
      end
      power_stats.each_pair do |stat, new_stats|
        next if !new_stats || new_stats.length == 0
        new_stat = new_stats.sample
        egg.iv[stat] = new_stat
        stats.delete(stat)   # Don't try to inherit this stat's IV again
        inherit_count -= 1
      end
      # Inherit the rest of the IVs
      chosen_stats = stats.sample(inherit_count)
      chosen_stats.each { |stat| egg.iv[stat] = [mother, father].sample.iv[stat] }
    end

    # Poké Balls can only be inherited from parents that are related to the
    # egg's species.
    # NOTE: This is how Poké Ball inheritance works in Gen 7+. Gens 5 and lower
    #       don't have Poké Ball inheritance at all. In Gen 6, only a female
    #       parent can pass down its Poké Ball. I don't think it's worth adding
    #       in these variations on the mechanic.
    # NOTE: The official games treat Nidoran M/F and Volbeat/Illumise as
    #       unrelated for the purpose of this mechanic. Essentials treats them
    #       as related and allows them to pass down their Poké Balls.
    def inherit_poke_ball(egg, mother, father)
      # mother = [mother, mother_ditto, mother_in_family]
      # father = [father, father_ditto, father_in_family]
      balls = []
      [mother, father].each do |parent|
        balls.push(parent[0].poke_ball) if parent[2]
      end
      balls.delete(:MASTERBALL)    # Can't inherit this Ball
      balls.delete(:CHERISHBALL)   # Can't inherit this Ball
      egg.poke_ball = balls.sample if !balls.empty?
    end

    # NOTE: There is a bug in Gen 8 that skips the original generation of an
    #       egg's personal ID if the Masuda Method/Shiny Charm can cause any
    #       rerolls. Essentials doesn't have this bug, meaning eggs are slightly
    #       more likely to be shiny (in Gen 8+ mechanics) than in Gen 8 itself.
    def set_shininess(egg, mother, father)
      shiny_retries = 0
      if father.owner.language != mother.owner.language
        shiny_retries += (Settings::MECHANICS_GENERATION >= 8) ? 6 : 5
      end
      shiny_retries += 2 if $bag.has?(:SHINYCHARM)
      return if shiny_retries == 0
      shiny_retries.times do
        break if egg.shiny?
        egg.shiny = nil   # Make it recalculate shininess
        egg.personalID = rand(2**16) | (rand(2**16) << 16)
      end
    end

    def set_pokerus(egg)
      egg.givePokerus if rand(65_536) < Settings::POKERUS_CHANCE
    end
  end

  #=============================================================================
  # A slot in the Day Care, which can contain a Pokémon.
  #=============================================================================
  class DayCareSlot
    attr_reader :pokemon

    def initialize
      reset
    end

    def reset
      @pokemon = nil
      @initial_level = 0
    end

    def deposit(pkmn)
      @pokemon = pkmn
      @pokemon.heal
      @pokemon.form = 0 if @pokemon.isSpecies?(:SHAYMIN)
      @initial_level = pkmn.level
    end

    def filled?
      return !@pokemon.nil?
    end

    def pokemon_name
      return (filled?) ? @pokemon.name : ""
    end

    def level_gain
      return (filled?) ? @pokemon.level - @initial_level : 0
    end

    def cost
      return (level_gain + 1) * 100
    end

    def choice_text
      return nil if !filled?
      if @pokemon.male?
        return _INTL("{1} (♂, Lv.{2})", @pokemon.name, @pokemon.level)
      elsif @pokemon.female?
        return _INTL("{1} (♀, Lv.{2})", @pokemon.name, @pokemon.level)
      end
      return _INTL("{1} (Lv.{2})", @pokemon.name, @pokemon.level)
    end

    def add_exp(amount = 1)
      return if !filled?
      max_exp = @pokemon.growth_rate.maximum_exp
      return if @pokemon.exp >= max_exp
      old_level = @pokemon.level
      @pokemon.exp += amount
      return if @pokemon.level == old_level
      @pokemon.calc_stats
      move_list = @pokemon.getMoveList
      move_list.each { |move| @pokemon.learn_move(move[1]) if move[0] == @pokemon.level }
    end
  end

  #=============================================================================

  attr_reader   :slots
  attr_accessor :egg_generated
  attr_accessor :step_counter
  attr_accessor :gain_exp
  attr_accessor :share_egg_moves   # For deposited Pokémon of the same species

  MAX_SLOTS = 2

  def initialize
    @slots = []
    MAX_SLOTS.times { @slots.push(DayCareSlot.new) }
    reset_egg_counters
    @gain_exp = Settings::DAY_CARE_POKEMON_GAIN_EXP_FROM_WALKING
    @share_egg_moves = Settings::DAY_CARE_POKEMON_CAN_SHARE_EGG_MOVES
  end

  def [](index)
    return @slots[index]
  end

  def reset_egg_counters
    @egg_generated = false
    @step_counter = 0
  end

  def count
    return @slots.select { |slot| slot.filled? }.length
  end

  def get_compatibility
    return compatibility
  end

  def generate_egg
    return nil if self.count != 2
    pkmn1, pkmn2 = pokemon_pair
    return EggGenerator.generate(pkmn1, pkmn2)
  end

  def share_egg_move
    return if count != 2
    pkmn1, pkmn2 = pokemon_pair
    return if pkmn1.species != pkmn2.species
    egg_moves1 = pkmn1.species_data.get_egg_moves
    egg_moves2 = pkmn2.species_data.get_egg_moves
    known_moves1 = []
    known_moves2 = []
    if pkmn2.numMoves < Pokemon::MAX_MOVES
      pkmn1.moves.each { |m| known_moves1.push(m.id) if egg_moves2.include?(m.id) && !pkmn2.hasMove?(m.id) }
    end
    if pkmn1.numMoves < Pokemon::MAX_MOVES
      pkmn2.moves.each { |m| known_moves2.push(m.id) if egg_moves1.include?(m.id) && !pkmn1.hasMove?(m.id) }
    end
    if !known_moves1.empty?
      if known_moves2.empty?
        pkmn2.learn_move(known_moves1[0])
      else
        learner = [[pkmn1, known_moves2[0]], [pkmn2, known_moves1[0]]].sample
        learner[0].learn_move(learner[1])
      end
    elsif !known_moves2.empty?
      pkmn1.learn_move(known_moves2[0])
    end
  end

  def update_on_step_taken
    @step_counter += 1
    if @step_counter >= 256
      @step_counter = 0
      # Make an egg available at the Day Care
      if !@egg_generated && count == 2
        compat = compatibility
        egg_chance = [0, 20, 50, 70][compat]
        egg_chance = [0, 40, 80, 88][compat] if $bag.has?(:OVALCHARM)
        @egg_generated = true if rand(100) < egg_chance
      end
      # Have one deposited Pokémon learn an egg move from the other
      # NOTE: I don't know what the chance of this happening is.
      share_egg_move if @share_egg_moves && rand(100) < 50
    end
    # Day Care Pokémon gain Exp/moves
    if @gain_exp
      @slots.each { |slot| slot.add_exp }
    end
  end

  #-----------------------------------------------------------------------------
  # Day Care
  
  def self.count
    return $PokemonGlobal.day_care.count
  end

  def self.egg_generated?
    return $PokemonGlobal.day_care.egg_generated
  end

  def self.reset_egg_counters
    $PokemonGlobal.day_care.reset_egg_counters
  end

  def self.get_details(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care.get_compatibility if compat_var > 0
  end

  def self.deposit(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw(index)
    day_care = $PokemonGlobal.day_care
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose(message, choice_var)
    day_care = $PokemonGlobal.day_care
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg
    day_care = $PokemonGlobal.day_care
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Additional Day Cares
  #-----------------------------------------------------------------------------
  # Kanto
  
  def self.count_Kanto
    return $PokemonGlobal.day_care_Kanto.count
  end

  def self.egg_generated_Kanto?
    return $PokemonGlobal.day_care_Kanto.egg_generated
  end

  def self.reset_egg_counters_Kanto
    $PokemonGlobal.day_care_Kanto.reset_egg_counters
  end

  def self.get_details_Kanto(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Kanto
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Kanto(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Kanto
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Kanto(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Kanto.get_compatibility if compat_var > 0
  end

  def self.deposit_Kanto(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Kanto
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Kanto(index)
    day_care = $PokemonGlobal.day_care_Kanto
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Kanto(message, choice_var)
    day_care = $PokemonGlobal.day_care_Kanto
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Kanto
    day_care = $PokemonGlobal.day_care_Kanto
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Sevii
  
  def self.count_Sevii
    return $PokemonGlobal.day_care_Sevii.count
  end

  def self.egg_generated_Sevii?
    return $PokemonGlobal.day_care_Sevii.egg_generated
  end

  def self.reset_egg_counters_Sevii
    $PokemonGlobal.day_care_Sevii.reset_egg_counters
  end

  def self.get_details_Sevii(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Sevii
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Sevii(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Sevii
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Sevii(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Sevii.get_compatibility if compat_var > 0
  end

  def self.deposit_Sevii(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Sevii
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Sevii(index)
    day_care = $PokemonGlobal.day_care_Sevii
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Sevii(message, choice_var)
    day_care = $PokemonGlobal.day_care_Sevii
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Sevii
    day_care = $PokemonGlobal.day_care_Sevii
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Johto
  
  def self.count_Johto
    return $PokemonGlobal.day_care_Johto.count
  end

  def self.egg_generated_Johto?
    return $PokemonGlobal.day_care_Johto.egg_generated
  end

  def self.reset_egg_counters_Johto
    $PokemonGlobal.day_care_Johto.reset_egg_counters
  end

  def self.get_details_Johto(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Johto
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Johto(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Johto
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Johto(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Johto.get_compatibility if compat_var > 0
  end

  def self.deposit_Johto(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Johto
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Johto(index)
    day_care = $PokemonGlobal.day_care_Johto
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Johto(message, choice_var)
    day_care = $PokemonGlobal.day_care_Johto
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Johto
    day_care = $PokemonGlobal.day_care_Johto
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Hoenn
  
  def self.count_Hoenn
    return $PokemonGlobal.day_care_Hoenn.count
  end

  def self.egg_generated_Hoenn?
    return $PokemonGlobal.day_care_Hoenn.egg_generated
  end

  def self.reset_egg_counters_Hoenn
    $PokemonGlobal.day_care_Hoenn.reset_egg_counters
  end

  def self.get_details_Hoenn(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Hoenn
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Hoenn(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Hoenn
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Hoenn(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Hoenn.get_compatibility if compat_var > 0
  end

  def self.deposit_Hoenn(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Hoenn
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Hoenn(index)
    day_care = $PokemonGlobal.day_care_Hoenn
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Hoenn(message, choice_var)
    day_care = $PokemonGlobal.day_care_Hoenn
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Hoenn
    day_care = $PokemonGlobal.day_care_Hoenn
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Sinnoh
  
  def self.count_Sinnoh
    return $PokemonGlobal.day_care_Sinnoh.count
  end

  def self.egg_generated_Sinnoh?
    return $PokemonGlobal.day_care_Sinnoh.egg_generated
  end

  def self.reset_egg_counters_Sinnoh
    $PokemonGlobal.day_care_Sinnoh.reset_egg_counters
  end

  def self.get_details_Sinnoh(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Sinnoh
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Sinnoh(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Sinnoh
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Sinnoh(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Sinnoh.get_compatibility if compat_var > 0
  end

  def self.deposit_Sinnoh(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Sinnoh
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Sinnoh(index)
    day_care = $PokemonGlobal.day_care_Sinnoh
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Sinnoh(message, choice_var)
    day_care = $PokemonGlobal.day_care_Sinnoh
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Sinnoh
    day_care = $PokemonGlobal.day_care_Sinnoh
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Unova
  
  def self.count_Unova
    return $PokemonGlobal.day_care_Unova.count
  end

  def self.egg_generated_Unova?
    return $PokemonGlobal.day_care_Unova.egg_generated
  end

  def self.reset_egg_counters_Unova
    $PokemonGlobal.day_care_Unova.reset_egg_counters
  end

  def self.get_details_Unova(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Unova
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Unova(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Unova
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Unova(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Unova.get_compatibility if compat_var > 0
  end

  def self.deposit_Unova(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Unova
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Unova(index)
    day_care = $PokemonGlobal.day_care_Unova
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Unova(message, choice_var)
    day_care = $PokemonGlobal.day_care_Unova
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Unova
    day_care = $PokemonGlobal.day_care_Unova
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Kalos
  
  def self.count_Kalos
    return $PokemonGlobal.day_care_Kalos.count
  end

  def self.egg_generated_Kalos?
    return $PokemonGlobal.day_care_Kalos.egg_generated
  end

  def self.reset_egg_counters_Kalos
    $PokemonGlobal.day_care_Kalos.reset_egg_counters
  end

  def self.get_details_Kalos(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Kalos
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Kalos(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Kalos
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Kalos(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Kalos.get_compatibility if compat_var > 0
  end

  def self.deposit_Kalos(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Kalos
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Kalos(index)
    day_care = $PokemonGlobal.day_care_Kalos
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Kalos(message, choice_var)
    day_care = $PokemonGlobal.day_care_Kalos
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Kalos
    day_care = $PokemonGlobal.day_care_Kalos
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Alola
  
  def self.count_Alola
    return $PokemonGlobal.day_care_Alola.count
  end

  def self.egg_generated_Alola?
    return $PokemonGlobal.day_care_Alola.egg_generated
  end

  def self.reset_egg_counters_Alola
    $PokemonGlobal.day_care_Alola.reset_egg_counters
  end

  def self.get_details_Alola(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Alola
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Alola(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Alola
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Alola(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Alola.get_compatibility if compat_var > 0
  end

  def self.deposit_Alola(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Alola
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Alola(index)
    day_care = $PokemonGlobal.day_care_Alola
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Alola(message, choice_var)
    day_care = $PokemonGlobal.day_care_Alola
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Alola
    day_care = $PokemonGlobal.day_care_Alola
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Galar1
  
  def self.count_Galar1
    return $PokemonGlobal.day_care_Galar1.count
  end

  def self.egg_generated_Galar1?
    return $PokemonGlobal.day_care_Galar1.egg_generated
  end

  def self.reset_egg_counters_Galar1
    $PokemonGlobal.day_care_Galar1.reset_egg_counters
  end

  def self.get_details_Galar1(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Galar1
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Galar1(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Galar1
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Galar1(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Galar1.get_compatibility if compat_var > 0
  end

  def self.deposit_Galar1(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Galar1
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Galar1(index)
    day_care = $PokemonGlobal.day_care_Galar1
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Galar1(message, choice_var)
    day_care = $PokemonGlobal.day_care_Galar1
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Galar1
    day_care = $PokemonGlobal.day_care_Galar1
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Galar2
  
  def self.count_Galar2
    return $PokemonGlobal.day_care_Galar2.count
  end

  def self.egg_generated_Galar2?
    return $PokemonGlobal.day_care_Galar2.egg_generated
  end

  def self.reset_egg_counters_Galar2
    $PokemonGlobal.day_care_Galar2.reset_egg_counters
  end

  def self.get_details_Galar2(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Galar2
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Galar2(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Galar2
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Galar2(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Galar2.get_compatibility if compat_var > 0
  end

  def self.deposit_Galar2(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Galar2
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Galar2(index)
    day_care = $PokemonGlobal.day_care_Galar2
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Galar2(message, choice_var)
    day_care = $PokemonGlobal.day_care_Galar2
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Galar2
    day_care = $PokemonGlobal.day_care_Galar2
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Orre
  
  def self.count_Orre
    return $PokemonGlobal.day_care_Orre.count
  end

  def self.egg_generated_Orre?
    return $PokemonGlobal.day_care_Orre.egg_generated
  end

  def self.reset_egg_counters_Orre
    $PokemonGlobal.day_care_Orre.reset_egg_counters
  end

  def self.get_details_Orre(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Orre
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Orre(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Orre
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Orre(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Orre.get_compatibility if compat_var > 0
  end

  def self.deposit_Orre(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Orre
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Orre(index)
    day_care = $PokemonGlobal.day_care_Orre
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Orre(message, choice_var)
    day_care = $PokemonGlobal.day_care_Orre
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Orre
    day_care = $PokemonGlobal.day_care_Orre
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Picnic
  
  def self.count_Picnic
    return $PokemonGlobal.day_care_Picnic.count
  end

  def self.egg_generated_Picnic?
    return $PokemonGlobal.day_care_Picnic.egg_generated
  end

  def self.reset_egg_counters_Picnic
    $PokemonGlobal.day_care_Picnic.reset_egg_counters
  end

  def self.get_details_Picnic(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Picnic
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Picnic(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Picnic
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Picnic(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Picnic.get_compatibility if compat_var > 0
  end

  def self.deposit_Picnic(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Picnic
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Picnic(index)
    day_care = $PokemonGlobal.day_care_Picnic
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Picnic(message, choice_var)
    day_care = $PokemonGlobal.day_care_Picnic
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Picnic
    day_care = $PokemonGlobal.day_care_Picnic
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # R10
  
  def self.count_R10
    return $PokemonGlobal.day_care_R10.count
  end

  def self.egg_generated_R10?
    return $PokemonGlobal.day_care_R10.egg_generated
  end

  def self.reset_egg_counters_R10
    $PokemonGlobal.day_care_R10.reset_egg_counters
  end

  def self.get_details_R10(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_R10
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_R10(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_R10
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_R10(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_R10.get_compatibility if compat_var > 0
  end

  def self.deposit_R10(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_R10
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_R10(index)
    day_care = $PokemonGlobal.day_care_R10
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_R10(message, choice_var)
    day_care = $PokemonGlobal.day_care_R10
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_R10
    day_care = $PokemonGlobal.day_care_R10
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # R11
  
  def self.count_R11
    return $PokemonGlobal.day_care_R11.count
  end

  def self.egg_generated_R11?
    return $PokemonGlobal.day_care_R11.egg_generated
  end

  def self.reset_egg_counters_R11
    $PokemonGlobal.day_care_R11.reset_egg_counters
  end

  def self.get_details_R11(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_R11
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_R11(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_R11
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_R11(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_R11.get_compatibility if compat_var > 0
  end

  def self.deposit_R11(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_R11
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_R11(index)
    day_care = $PokemonGlobal.day_care_R11
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_R11(message, choice_var)
    day_care = $PokemonGlobal.day_care_R11
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_R11
    day_care = $PokemonGlobal.day_care_R11
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # R12
  
  def self.count_R12
    return $PokemonGlobal.day_care_R12.count
  end

  def self.egg_generated_R12?
    return $PokemonGlobal.day_care_R12.egg_generated
  end

  def self.reset_egg_counters_R12
    $PokemonGlobal.day_care_R12.reset_egg_counters
  end

  def self.get_details_R12(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_R12
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_R12(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_R12
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_R12(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_R12.get_compatibility if compat_var > 0
  end

  def self.deposit_R12(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_R12
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_R12(index)
    day_care = $PokemonGlobal.day_care_R12
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_R12(message, choice_var)
    day_care = $PokemonGlobal.day_care_R12
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_R12
    day_care = $PokemonGlobal.day_care_R12
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # R13
  
  def self.count_R13
    return $PokemonGlobal.day_care_R13.count
  end

  def self.egg_generated_R13?
    return $PokemonGlobal.day_care_R13.egg_generated
  end

  def self.reset_egg_counters_R13
    $PokemonGlobal.day_care_R13.reset_egg_counters
  end

  def self.get_details_R13(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_R13
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_R13(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_R13
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_R13(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_R13.get_compatibility if compat_var > 0
  end

  def self.deposit_R13(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_R13
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_R13(index)
    day_care = $PokemonGlobal.day_care_R13
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_R13(message, choice_var)
    day_care = $PokemonGlobal.day_care_R13
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_R13
    day_care = $PokemonGlobal.day_care_R13
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # R14
  
  def self.count_R14
    return $PokemonGlobal.day_care_R14.count
  end

  def self.egg_generated_R14?
    return $PokemonGlobal.day_care_R14.egg_generated
  end

  def self.reset_egg_counters_R14
    $PokemonGlobal.day_care_R14.reset_egg_counters
  end

  def self.get_details_R14(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_R14
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_R14(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_R14
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_R14(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_R14.get_compatibility if compat_var > 0
  end

  def self.deposit_R14(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_R14
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_R14(index)
    day_care = $PokemonGlobal.day_care_R14
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_R14(message, choice_var)
    day_care = $PokemonGlobal.day_care_R14
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_R14
    day_care = $PokemonGlobal.day_care_R14
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # R15
  
  def self.count_R15
    return $PokemonGlobal.day_care_R15.count
  end

  def self.egg_generated_R15?
    return $PokemonGlobal.day_care_R15.egg_generated
  end

  def self.reset_egg_counters_R15
    $PokemonGlobal.day_care_R15.reset_egg_counters
  end

  def self.get_details_R15(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_R15
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_R15(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_R15
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_R15(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_R15.get_compatibility if compat_var > 0
  end

  def self.deposit_R15(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_R15
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_R15(index)
    day_care = $PokemonGlobal.day_care_R15
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_R15(message, choice_var)
    day_care = $PokemonGlobal.day_care_R15
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_R15
    day_care = $PokemonGlobal.day_care_R15
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Spare1
  
  def self.count_Spare1
    return $PokemonGlobal.day_care_Spare1.count
  end

  def self.egg_generated_Spare1?
    return $PokemonGlobal.day_care_Spare1.egg_generated
  end

  def self.reset_egg_counters_Spare1
    $PokemonGlobal.day_care_Spare1.reset_egg_counters
  end

  def self.get_details_Spare1(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Spare1
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Spare1(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Spare1
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Spare1(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Spare1.get_compatibility if compat_var > 0
  end

  def self.deposit_Spare1(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Spare1
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Spare1(index)
    day_care = $PokemonGlobal.day_care_Spare1
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Spare1(message, choice_var)
    day_care = $PokemonGlobal.day_care_Spare1
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Spare1
    day_care = $PokemonGlobal.day_care_Spare1
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Spare2
  
  def self.count_Spare2
    return $PokemonGlobal.day_care_Spare2.count
  end

  def self.egg_generated_Spare2?
    return $PokemonGlobal.day_care_Spare2.egg_generated
  end

  def self.reset_egg_counters_Spare2
    $PokemonGlobal.day_care_Spare2.reset_egg_counters
  end

  def self.get_details_Spare2(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Spare2
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Spare2(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Spare2
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Spare2(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Spare2.get_compatibility if compat_var > 0
  end

  def self.deposit_Spare2(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Spare2
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Spare2(index)
    day_care = $PokemonGlobal.day_care_Spare2
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Spare2(message, choice_var)
    day_care = $PokemonGlobal.day_care_Spare2
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Spare2
    day_care = $PokemonGlobal.day_care_Spare2
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Spare3
  
  def self.count_Spare3
    return $PokemonGlobal.day_care_Spare3.count
  end

  def self.egg_generated_Spare3?
    return $PokemonGlobal.day_care_Spare3.egg_generated
  end

  def self.reset_egg_counters_Spare3
    $PokemonGlobal.day_care_Spare3.reset_egg_counters
  end

  def self.get_details_Spare3(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Spare3
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Spare3(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Spare3
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Spare3(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Spare3.get_compatibility if compat_var > 0
  end

  def self.deposit_Spare3(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Spare3
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Spare3(index)
    day_care = $PokemonGlobal.day_care_Spare3
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Spare3(message, choice_var)
    day_care = $PokemonGlobal.day_care_Spare3
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Spare3
    day_care = $PokemonGlobal.day_care_Spare3
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Spare4
  
  def self.count_Spare4
    return $PokemonGlobal.day_care_Spare4.count
  end

  def self.egg_generated_Spare4?
    return $PokemonGlobal.day_care_Spare4.egg_generated
  end

  def self.reset_egg_counters_Spare4
    $PokemonGlobal.day_care_Spare4.reset_egg_counters
  end

  def self.get_details_Spare4(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Spare4
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Spare4(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Spare4
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Spare4(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Spare4.get_compatibility if compat_var > 0
  end

  def self.deposit_Spare4(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Spare4
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Spare4(index)
    day_care = $PokemonGlobal.day_care_Spare4
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Spare4(message, choice_var)
    day_care = $PokemonGlobal.day_care_Spare4
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Spare4
    day_care = $PokemonGlobal.day_care_Spare4
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------
  # Spare5
  
  def self.count_Spare5
    return $PokemonGlobal.day_care_Spare5.count
  end

  def self.egg_generated_Spare5?
    return $PokemonGlobal.day_care_Spare5.egg_generated
  end

  def self.reset_egg_counters_Spare5
    $PokemonGlobal.day_care_Spare5.reset_egg_counters
  end

  def self.get_details_Spare5(index, name_var, cost_var)
    day_care = $PokemonGlobal.day_care_Spare5
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[cost_var] = day_care[index].cost if cost_var > 0
  end

  def self.get_level_gain_Spare5(index, name_var, level_var)
    day_care = $PokemonGlobal.day_care_Spare5
    $game_variables[name_var] = day_care[index].pokemon_name if name_var > 0
    $game_variables[level_var] = day_care[index].level_gain if level_var > 0
  end

  def self.get_compatibility_Spare5(compat_var)
    $game_variables[compat_var] = $PokemonGlobal.day_care_Spare5.get_compatibility if compat_var > 0
  end

  def self.deposit_Spare5(party_index)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care_Spare5
    pkmn = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    day_care.slots.each do |slot|
      next if slot.filled?
      slot.deposit(pkmn)
      $player.party.delete_at(party_index)
      day_care.reset_egg_counters
      return
    end
    raise _INTL("No room to deposit a Pokémon.")
  end

  def self.withdraw_Spare5(index)
    day_care = $PokemonGlobal.day_care_Spare5
    slot = day_care[index]
    if !slot.filled?
      raise _INTL("No Pokémon found in slot {1}.", index)
    elsif $player.party_full?
      raise _INTL("No room in party for Pokémon.")
    end
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care.reset_egg_counters
  end

  def self.choose_Spare5(message, choice_var)
    day_care = $PokemonGlobal.day_care_Spare5
    case day_care.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      day_care.slots.each_with_index { |slot, i| $game_variables[choice_var] = i if slot.filled? }
    else
      commands = []
      indices = []
      day_care.slots.each_with_index do |slot, i|
        choice_text = slot.choice_text
        next if !choice_text
        commands.push(choice_text)
        indices.push(i)
      end
      commands.push(_INTL("CANCEL"))
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg_Spare5
    day_care = $PokemonGlobal.day_care_Spare5
    egg = day_care.generate_egg
    raise _INTL("Couldn't generate the egg.") if egg.nil?
    raise _INTL("No room in party for egg.") if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters
  end

  #-----------------------------------------------------------------------------

  private

  def pokemon_pair
    pkmn1 = nil
    pkmn2 = nil
    @slots.each do |slot|
      next if !slot.filled?
      if pkmn1.nil?
        pkmn1 = slot.pokemon
      else
        pkmn2 = slot.pokemon
      end
    end
    raise _INTL("Couldn't find 2 deposited Pokémon.") if pkmn2.nil?
    return pkmn1, pkmn2
  end

  def pokemon_in_ditto_egg_group?(pkmn)
    return pkmn.species_data.egg_groups.include?(:Ditto)
  end

  def compatible_gender?(pkmn1, pkmn2)
    return true if pkmn1.female? && pkmn2.male?
    return true if pkmn1.male? && pkmn2.female?
    ditto1 = pokemon_in_ditto_egg_group?(pkmn1)
    ditto2 = pokemon_in_ditto_egg_group?(pkmn2)
    return true if ditto1 && !ditto2
    return true if ditto2 && !ditto1
    return false
  end

  def compatibility
    return 0 if self.count != 2
    # Find the Pokémon whose compatibility is being calculated
    pkmn1, pkmn2 = pokemon_pair
    # Shadow Pokémon cannot breed
    return 0 if pkmn1.shadowPokemon? || pkmn2.shadowPokemon?
    # Pokémon in the Undiscovered egg group cannot breed
    egg_groups1 = pkmn1.species_data.egg_groups
    egg_groups2 = pkmn2.species_data.egg_groups
    return 0 if egg_groups1.include?(:Undiscovered) ||
                egg_groups2.include?(:Undiscovered)
    # Pokémon that don't share an egg group (and neither is in the Ditto group)
    # cannot breed
    return 0 if !egg_groups1.include?(:Ditto) &&
                !egg_groups2.include?(:Ditto) &&
                (egg_groups1 & egg_groups2).length == 0
    # Pokémon with incompatible genders cannot breed
    return 0 if !compatible_gender?(pkmn1, pkmn2)
    # Pokémon can breed; calculate a compatibility factor
    ret = 1
    ret += 1 if pkmn1.species == pkmn2.species
    ret += 1 if pkmn1.owner.id != pkmn2.owner.id
    return ret
  end
end

#===============================================================================
# With each step taken, add Exp to Pokémon in the Day Care and try to generate
# an egg.
#===============================================================================
EventHandlers.add(:on_player_step_taken, :update_day_care,
  proc {
    $PokemonGlobal.day_care.update_on_step_taken
    $PokemonGlobal.day_care_Kanto.update_on_step_taken
    $PokemonGlobal.day_care_Sevii.update_on_step_taken
    $PokemonGlobal.day_care_Johto.update_on_step_taken
    $PokemonGlobal.day_care_Hoenn.update_on_step_taken
    $PokemonGlobal.day_care_Sinnoh.update_on_step_taken
    $PokemonGlobal.day_care_Unova.update_on_step_taken
    $PokemonGlobal.day_care_Kalos.update_on_step_taken
    $PokemonGlobal.day_care_Alola.update_on_step_taken
    $PokemonGlobal.day_care_Galar1.update_on_step_taken
    $PokemonGlobal.day_care_Galar2.update_on_step_taken
    $PokemonGlobal.day_care_Orre.update_on_step_taken
    $PokemonGlobal.day_care_Picnic.update_on_step_taken
    $PokemonGlobal.day_care_R10.update_on_step_taken
    $PokemonGlobal.day_care_R11.update_on_step_taken
    $PokemonGlobal.day_care_R12.update_on_step_taken
    $PokemonGlobal.day_care_R13.update_on_step_taken
    $PokemonGlobal.day_care_R14.update_on_step_taken
    $PokemonGlobal.day_care_R15.update_on_step_taken
    $PokemonGlobal.day_care_Spare1.update_on_step_taken
    $PokemonGlobal.day_care_Spare2.update_on_step_taken
    $PokemonGlobal.day_care_Spare3.update_on_step_taken
    $PokemonGlobal.day_care_Spare4.update_on_step_taken
    $PokemonGlobal.day_care_Spare5.update_on_step_taken
  }
)
