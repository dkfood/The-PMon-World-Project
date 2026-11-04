#===============================================================================
# Load various wild battle music
#===============================================================================
# wildParty is an array of Pokémon objects.
def pbGetWildBattleBGM(_wildParty)
  return $PokemonGlobal.nextBattleBGM.clone if $PokemonGlobal.nextBattleBGM
  ret = nil
  if !ret
    # Check map metadata
    music = $game_map.metadata&.wild_battle_BGM
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check regional metadata
    music = Settings::REGION_MUSIC_BATTLE_WILD_ARRAY[pbGetCurrentRegion]
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check global metadata
    music = GameData::Metadata.get.wild_battle_BGM
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !music || music == ""
    music = Settings::REGION_MUSIC_BATTLE_WILD_ARRAY[0]
  end
  ret = pbStringToAudioFile(music) if !ret
  return ret
end

def pbGetWildVictoryBGM
  if $PokemonGlobal.nextBattleVictoryBGM
    return $PokemonGlobal.nextBattleVictoryBGM.clone
  end
  ret = nil
  if !ret
    # Check map metadata
    music = $game_map.metadata&.wild_victory_BGM
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check regional metadata
    music = Settings::REGION_MUSIC_BATTLE_WILD_VICTORY_ARRAY[pbGetCurrentRegion]
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check global metadata
    music = GameData::Metadata.get.wild_victory_BGM
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !music || music == ""
    music = Settings::REGION_MUSIC_BATTLE_WILD_VICTORY_ARRAY[0]
  end
  ret = pbStringToAudioFile(music) if !ret
  ret.name = "../../Audio/BGM/" + ret.name
  return ret
end

def pbGetWildCaptureME
  if $PokemonGlobal.nextBattleCaptureME
    return $PokemonGlobal.nextBattleCaptureME.clone
  end
  ret = nil
  if !ret
    # Check map metadata
    music = $game_map.metadata&.wild_capture_ME
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check regional metadata
    music = Settings::REGION_MUSIC_POKEMON_CAPTURED_ARRAY[pbGetCurrentRegion]
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check global metadata
    music = GameData::Metadata.get.wild_capture_ME
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !music || music == ""
    music = Settings::REGION_MUSIC_POKEMON_CAPTURED_ARRAY[0]
  end
  ret = pbStringToAudioFile(music) if !ret
  ret.name = "../../Audio/ME/" + ret.name
  return ret
end

#===============================================================================
# Load/play various trainer battle music
#===============================================================================
def pbPlayTrainerIntroBGM(trainer_type)
  trainer_type_data = GameData::TrainerType.get(trainer_type)
  if !nil_or_empty?(trainer_type_data.intro_BGM)
    bgm = pbStringToAudioFile(trainer_type_data.intro_BGM)
  end
  if nil_or_empty?(trainer_type_data.intro_BGM)
    # Define music based on region and gender metadata
    if trainer_type_data.gender == 0
      music = Settings::REGION_MUSIC_BATTLE_TRAINER_INTRO_M_ARRAY[pbGetCurrentRegion]
      if !music || music == ""
        music = Settings::REGION_MUSIC_BATTLE_TRAINER_INTRO_M_ARRAY[0]
      end
    end
    if trainer_type_data.gender == 1
      music = Settings::REGION_MUSIC_BATTLE_TRAINER_INTRO_F_ARRAY[pbGetCurrentRegion]
      if !music || music == ""
        music = Settings::REGION_MUSIC_BATTLE_TRAINER_INTRO_F_ARRAY[0]
      end
    end
  end
  if !music || music == ""
    music = Settings::REGION_MUSIC_BATTLE_TRAINER_INTRO_ARRAY[pbGetCurrentRegion]
  end
  if !music || music == ""
    music = Settings::REGION_MUSIC_BATTLE_TRAINER_INTRO_ARRAY[0]
  end
  bgm = pbStringToAudioFile(music) if !bgm
  if !$game_temp.memorized_bgm
    $game_temp.memorized_bgm = $game_system.getPlayingBGM
    $game_temp.memorized_bgm_position = (Audio.bgm_pos rescue 0)
  end
  pbBGMPlay(bgm)
end

# Can be a Player, NPCTrainer or an array of them.
def pbGetTrainerBattleBGM(trainer)
  return $PokemonGlobal.nextBattleBGM.clone if $PokemonGlobal.nextBattleBGM
  ret = nil
  music = nil
  trainerarray = (trainer.is_a?(Array)) ? trainer : [trainer]
  trainerarray.each do |t|
    trainer_type_data = GameData::TrainerType.get(t.trainer_type)
    music = trainer_type_data.battle_BGM if trainer_type_data.battle_BGM
  end
  ret = pbStringToAudioFile(music) if music && music != ""
  if !ret
    # Check map metadata
    music = $game_map.metadata&.trainer_battle_BGM
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check regional metadata
    music = Settings::REGION_MUSIC_BATTLE_TRAINER_ARRAY[pbGetCurrentRegion]
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check global metadata
    music = GameData::Metadata.get.trainer_battle_BGM
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !music || music == ""
    music = Settings::REGION_MUSIC_BATTLE_TRAINER_ARRAY[0]
  end
  ret = pbStringToAudioFile(music) if !ret
  return ret
end

def pbGetTrainerBattleBGMFromType(trainertype)
  return $PokemonGlobal.nextBattleBGM.clone if $PokemonGlobal.nextBattleBGM
  trainer_type_data = GameData::TrainerType.get(trainertype)
  ret = trainer_type_data.battle_BGM if trainer_type_data.battle_BGM
  if !ret
    # Check map metadata
    music = $game_map.metadata&.trainer_battle_BGM
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check regional metadata
    music = Settings::REGION_MUSIC_BATTLE_TRAINER_ARRAY[pbGetCurrentRegion]
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check global metadata
    music = GameData::Metadata.get.trainer_battle_BGM
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !music || music == ""
    music = Settings::REGION_MUSIC_BATTLE_TRAINER_ARRAY[0]
  end
  ret = pbStringToAudioFile(music) if !ret
  return ret
end

# Can be a Player, NPCTrainer or an array of them.
def pbGetTrainerVictoryBGM(trainer)
  if $PokemonGlobal.nextBattleVictoryBGM
    return $PokemonGlobal.nextBattleVictoryBGM.clone
  end
  music = nil
  trainerarray = (trainer.is_a?(Array)) ? trainer : [trainer]
  trainerarray.each do |t|
    trainer_type_data = GameData::TrainerType.get(t.trainer_type)
    music = trainer_type_data.victory_BGM if trainer_type_data.victory_BGM
  end
  ret = nil
  ret = pbStringToAudioFile(music) if music && music != ""
  if !ret
    # Check map metadata
    music = $game_map.metadata&.trainer_victory_BGM
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check regional metadata
    music = Settings::REGION_MUSIC_BATTLE_TRAINER_VICTORY_ARRAY[pbGetCurrentRegion]
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !ret
    # Check global metadata
    music = GameData::Metadata.get.trainer_victory_BGM
    ret = pbStringToAudioFile(music) if music && music != ""
  end
  if !music || music == ""
    music = Settings::REGION_MUSIC_BATTLE_TRAINER_VICTORY_ARRAY[0]
  end
  ret = pbStringToAudioFile(music) if !ret
  ret.name = "../../Audio/BGM/" + ret.name
  return ret
end
