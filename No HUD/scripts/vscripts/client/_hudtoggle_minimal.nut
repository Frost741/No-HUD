function main()
{
	level.hudToggle_hidden <- true
	level.hudToggle_lastNativeState <- null

	// Safety net, every map load, any mode: cl_drawhud/crosshair are plain client
	// ConVars - unlike the native togglehud toggle (CE_FLAG_PERMANENT_HIDEHUD, a
	// cinematic flag on the player ENTITY, which always starts fresh/off on a new
	// entity, so it's never actually "stuck") they persist on the client across
	// disconnects and level loads. If something hid them mid-match and the normal
	// show-path never got to run (e.g. the player quits out before any of this mod's
	// own triggers fire), they'd otherwise stay stuck at 0 into whatever loads next.
	// Checked once, right here, before anything else in this file runs: if the HUD is
	// already on, this does nothing and the rest of the mod behaves exactly as normal
	// for the new match. Only touches these two ConVars directly - deliberately does
	// NOT go through HudToggleMinimal_Apply()/togglehud, since the entity flag isn't
	// the thing that's stuck here and toggling it on top would desync the two.
	// Always force cl_drawhud/crosshair back to 1 once per map load, after waiting
	// for a valid local player (see HudToggleMinimal_ForceShowConVarsOnLoad() below -
	// three uploaded crash logs in a row confirm GetConVarInt() can't be used to
	// check these first, so there's no read, just an unconditional, harmless set).
	thread HudToggleMinimal_ForceShowConVarsOnLoad()

	// Permanently off, every map/mode. ToggleGrenadeIndicators() is globalized by
	// CORE's client/cl_player.nut; calling it once per map load flips
	// level.grenadeIndicatorEnabled from its default true to false, which is the only
	// gate DamageIndicators() checks before drawing the grenade threat arrow.
	ToggleGrenadeIndicators()
	thread HudToggleMinimal_DisableHitmarkers()
	thread HudToggleMinimal_WatchForTitanEmbark()

	// Safety net alongside the IsTitan() poll above: CE_FLAG_DISEMBARK covers
	// leaving a Titan specifically, including ejecting ("катапультирование") - set
	// natively, not from any script AddCinematicFlag call. In case that doesn't
	// flip IsTitan() in time (or at all) to be caught by the poll.
	AddCinematicEventFlagChangedCallback( CE_FLAG_DISEMBARK, HudToggleMinimal_OnDisembarkFlagChanged )

	// mp/_classic_mp.nut: SpawnPlayerIntoDropship() sets this flag right as the player
	// is put into the dropship ("прыжок в расположение" starts playing), and only
	// removes it once the player has landed after the jump-out animation. Fires on the
	// very first spawn and again on every respawn. Any map, as long as the mode is
	// Attrition / Pilot Hunter / Hardpoint Domination - other modes don't get this
	// hide. NOT used on mp_npe - that map overrides the intro spawn function entirely
	// (see the CE_FLAG_INTRO block below), so SpawnPlayerIntoDropship() and this flag
	// never fire there at all.
	if ( HudToggleMinimal_IsTargetMode() )
		AddCinematicEventFlagChangedCallback( CE_FLAG_CLASSIC_MP_SPAWNING, HudToggleMinimal_OnSpawnFlagChanged )

	// CE_FLAG_INTRO is set on connect (mp/_classic_mp.nut's
	// ClassicMP_DropshipIntro_OnClientConnectedFunc(), before eGameState even reaches
	// Prematch) - the establishing-shot cutscene before the dropship ride. HUD is
	// visible by default there too. On mp_wargames specifically, hide it 2.5s into the
	// cutscene (see HudToggleMinimal_OnIntroFlagChanged). mp_wargames isn't actually
	// one of campaign_carousel's 9 maps (checked playlists.txt - "CERTIFICATION" turned
	// out to be mp_npe's English title, MP_NPE_MULTIPLAYER, not mp_wargames at all), so
	// this only ever fires when mp_wargames is played directly in Attrition/TDM/CP.
	if ( GetMapName() == "mp_wargames" && HudToggleMinimal_IsTargetMode() )
		AddCinematicEventFlagChangedCallback( CE_FLAG_INTRO, HudToggleMinimal_OnIntroFlagChanged )

	// mp_npe ("CERTIFICATION"): mp/mp_npe_multiplayer.nut completely replaces the
	// classic MP intro spawn function (ClassicMP_SetIntroPlayerSpawnFunc) with its own
	// ~25s "training pod" cutscene (NPE_ClassicMPIntroSpawn -> PlayerWatchPodIntro),
	// which sets CE_FLAG_INTRO itself and clears it only once that whole sequence ends
	// and players are teleported to the real spawns - no separate dropship ride after
	// it. Only playable in FFA/Gun Game (playlists.txt's all_mini block), neither of
	// which HudToggleMinimal_IsTargetMode() matches, so this is unconditional on mode.
	if ( GetMapName() == "mp_npe" )
		AddCinematicEventFlagChangedCallback( CE_FLAG_INTRO, HudToggleMinimal_OnIntroFlagChanged )

	// Campaign (campaign_carousel playlist), not on mp_wargames (handled above): 9
	// specific missions have measured, per-mission cutscene delays - not mode-gated,
	// since the Campaign carousel isn't limited to Attrition/TDM/CP. Any other
	// Campaign map falls back to an instant hide on CE_FLAG_INTRO, same idea as
	// mp_wargames just without a measured delay.
	// The 9 timed missions don't need this registered - HudToggleMinimal_OnGameStateChanged()
	// handles their hide, triggered off eGameState.Prematch (right after WaitingForPlayers).
	if ( GetCurrentPlaylistName() == CAMPAIGN && GetMapName() != "mp_wargames" && !HudToggleMinimal_IsTimedCampaignMission() )
		AddCinematicEventFlagChangedCallback( CE_FLAG_INTRO, HudToggleMinimal_OnIntroFlagChanged )

	// eGameState order: ... WinnerDetermined, Epilogue, Postmatch. Postmatch is when
	// the epilogue cinematic ends and the post-game player/stats table shows - bring
	// the HUD back so it's not fighting that screen. Next map load resets everything
	// (level.hudToggle_hidden back to true) and the cycle (hide on spawn, show on
	// Postmatch) repeats for the new match.
	RegisterServerVarChangeCallback( "gameState", HudToggleMinimal_OnGameStateChanged )
}

function HudToggleMinimal_IsTargetMode()
{
	// GameRules.GetGameMode() directly, not the GAMETYPE global - GAMETYPE is a plain
	// slot set by _settings.nut, and this file's IncludeFile closure isn't guaranteed
	// to see it (unlike CE_FLAG_*/eGameState, which are consts - always visible).
	// COOPERATIVE ("Оборона фронтира"/Frontier Defense) and TITAN_BRAWL/TITAN_BRAWL_AUTO
	// ("Битва титанов"/Titan Brawl) added here.
	local mode = GameRules.GetGameMode()
	return ( mode == ATTRITION || mode == TEAM_DEATHMATCH || mode == CAPTURE_POINT
		|| mode == COOPERATIVE || mode == TITAN_BRAWL || mode == TITAN_BRAWL_AUTO )
}

function HudToggleMinimal_ApplyDelayedOnCoopGameOver()
{
	wait 13.0
	level.hudToggle_hidden = false
	HudToggleMinimal_Apply( false )
}

function HudToggleMinimal_ForceShowConVarsOnLoad()
{
	local localPlayer = GetLocalClientPlayer()
	while ( !IsValid( localPlayer ) )
	{
		wait 0
		localPlayer = GetLocalClientPlayer()
	}

	// No read-first check: GetConVarInt()/GetConVarBool() only work on script-
	// registered ConVars (CORE's own "delta_*" settings) - confirmed by two more
	// crashes trying to use it on cl_drawhud/crosshair specifically, plain engine
	// ConVars that were never exposed to the VM's convar table at all. Setting them
	// to 1 when they're already 1 is a harmless no-op, so there's nothing to check.
	localPlayer.ClientCommand( "cl_drawhud 1" )
	localPlayer.ClientCommand( "crosshair 1" )
}

function HudToggleMinimal_IsTitanSpawnMode()
{
	local mode = GameRules.GetGameMode()
	return ( mode == TITAN_BRAWL || mode == TITAN_BRAWL_AUTO )
}

function HudToggleMinimal_ApplyDelayedOnTitanBrawlWait()
{
	wait 1.5
	HudToggleMinimal_Apply( level.hudToggle_hidden )
}

function HudToggleMinimal_IsTimedCampaignMission()
{
	switch ( GetMapName() )
	{
		case "mp_fracture":		// "Налёт с пит-стопом"
		case "mp_colony":		// "Колония"
		case "mp_relic":		// "Одиссей"
		case "mp_outpost_207":	// "Штурм Стража"
		case "mp_boneyard":		// "Логово драконов"
		case "mp_angel_city":	// "За Баркером"
		case "mp_airbase":		// "Три башни"
		case "mp_o2":			// "Битва при Деметре"
		case "mp_corporate":	// "Искусственные люди"
			return true
	}
	return false
}

// Measured per-mission cutscene delay, from the moment WaitingForPlayers ends
// (eGameState.Prematch, since campaign_carousel's classic_mp playlist var is 0).
// Same delay for both teams on every mission here.
function HudToggleMinimal_GetCampaignIntroDelay()
{
	local map = GetMapName()

	switch ( map )
	{
		case "mp_fracture":		return 6.5
		case "mp_colony":		return 9.0
		case "mp_relic":		return 9.2
		case "mp_outpost_207":	return 21.0
		case "mp_boneyard":		return 14.0
		case "mp_angel_city":	return 8.5
		case "mp_airbase":		return 6.5
		case "mp_o2":			return 5.5
		case "mp_corporate":	return 9.0
	}

	return null
}

function HudToggleMinimal_DisableHitmarkers()
{
	// main() runs before entities exist, so GetLocalClientPlayer() isn't valid yet -
	// wait for it, then send the command the same way HudToggleMinimal_Apply() does
	// (localPlayer.ClientCommand(...), not a bare ClientCommand(...) call).
	// delta_hud_show_hitmarkers is the ConVar client/cl_player.nut's
	// TryShowHitIndicator() reads before showing a hit marker; 0 is HITMARKER_DISABLED.
	local localPlayer = GetLocalClientPlayer()
	while ( !IsValid( localPlayer ) )
	{
		wait 0
		localPlayer = GetLocalClientPlayer()
	}

	localPlayer.ClientCommand( "delta_hud_show_hitmarkers 0" )
}

function HudToggleMinimal_WatchForTitanEmbark()
{
	// Confirmed in-game working at 3s. Dash/Core did nothing at all while piloting a
	// Titan with the HUD permanently hidden; with the hide disabled entirely (HUD
	// always shown), dash/Core work fine - so cl_drawhud/crosshair/togglehud being 0
	// breaks them outright, for as long as they're 0.
	//
	// Shows the HUD on embark or disembark/ejecting (both 1.0s windows for now),
	// then hides again.
	//
	// Re-fetches localPlayer every iteration instead of caching it once and
	// return-ing on !IsValid() - that used to permanently kill this thread the
	// moment the local player entity went invalid even briefly (e.g. between
	// rounds, without a full map reload restarting main()), so embark/disembark
	// stopped doing anything for the rest of the session after the first round.
	local wasTitan = false
	local hasWasTitan = false

	for ( ;; )
	{
		local localPlayer = GetLocalClientPlayer()
		if ( !IsValid( localPlayer ) )
		{
			hasWasTitan = false
			wait 0
			continue
		}

		local isTitan = localPlayer.IsTitan()

		if ( !hasWasTitan )
		{
			wasTitan = isTitan
			hasWasTitan = true
		}

		if ( isTitan && !wasTitan )
		{
			HudToggleMinimal_Apply( false )
			thread HudToggleMinimal_ApplyDelayedOnTitanEmbark( localPlayer )
		}
		else if ( !isTitan && wasTitan )
		{
			HudToggleMinimal_Apply( false )
			thread HudToggleMinimal_ApplyDelayedOnTitanDisembark( localPlayer )
		}

		wasTitan = isTitan
		wait 0
	}
}

function HudToggleMinimal_ApplyDelayedOnTitanEmbark( player )
{
	player.EndSignal( "OnDestroy" )
	wait 0.1
	HudToggleMinimal_Apply( level.hudToggle_hidden )
}

function HudToggleMinimal_ApplyDelayedOnTitanDisembark( player )
{
	player.EndSignal( "OnDestroy" )
	wait 0.1
	HudToggleMinimal_Apply( level.hudToggle_hidden )
}

function HudToggleMinimal_OnDisembarkFlagChanged( player )
{
	if ( player != GetLocalClientPlayer() )
		return

	// only act when the flag just turned ON
	if ( !( player.GetCinematicEventFlags() & CE_FLAG_DISEMBARK ) )
		return

	HudToggleMinimal_Apply( false )
	thread HudToggleMinimal_ApplyDelayedOnTitanDisembark( player )
}

function HudToggleMinimal_OnGameStateChanged()
{
	local gameState = GetGameState()

	// Titan Brawl / Titan Brawl Auto: Riff_ForceSetSpawnAsTitan( eSpawnAsTitan.Always )
	// (mp/_gamemode_titan_brawl.nut) makes ShouldIntroSpawnAsTitan()/ShouldSpawnAsTitan()
	// true, which makes ClassicMP_Dropship_IntroLevelSetupFunc(), CanSpawnIntoIntroDropship()
	// and CanSpawnIntoWaveSpawnDropship() all bail out before SpawnPlayerIntoDropship() is
	// ever called - CE_FLAG_CLASSIC_MP_SPAWNING (step 2's trigger) is only ever set inside
	// that function, so it never fires here. Players just sit on the
	// "#HUD_WAITING_FOR_PLAYERS" screen (client/_cl_misc_hud.nut) with no dropship/jump-in
	// cutscene at all. Hide 1.5s after that state is entered instead.
	if ( gameState == eGameState.WaitingForPlayers )
	{
		if ( HudToggleMinimal_IsTitanSpawnMode() )
			thread HudToggleMinimal_ApplyDelayedOnTitanBrawlWait()
		return
	}

	// Campaign: WaitingForPlayers just ended. mp/_gamestate.nut's
	// GameRulesThink_WaitingForPlayers() only goes to PickLoadout when
	// GetClassicMPMode() is true - campaign_carousel's playlist var "classic_mp" is
	// "0", so it always goes straight to Prematch instead. The cutscene starts here.
	// Only for the 8 missions with a measured delay
	// (HudToggleMinimal_IsTimedCampaignMission() gated this registration in main()).
	// GetCampaignIntroDelay() is keyed purely on map name, with no playlist check - some
	// of its 9 maps (e.g. mp_airbase, mp_angel_city) are also played in other playlists
	// (Titan Brawl, Attrition, etc.), so this whole branch must stay gated to the
	// Campaign playlist, or those other modes wrongly take the Campaign timing path
	// below and skip the round-start hide entirely (confirmed in-game: HUD never hid
	// at all playing Titan Brawl on mp_airbase).
	if ( gameState == eGameState.Prematch )
	{
		if ( GetCurrentPlaylistName() == CAMPAIGN )
		{
			local delay = HudToggleMinimal_GetCampaignIntroDelay()
			if ( delay != null )
				thread HudToggleMinimal_ApplyDelayedOnCampaignIntro( delay )
		}
		return
	}

	// Round start: the prematch countdown ends, gameState reaches Playing, and
	// controls are handed to the player - independent of any dropship/respawn flag,
	// CORE itself shows the HUD here (cl_drawhud 1; togglehud). Hide it again 2.1s
	// after that happens. Skipped for the timed Campaign missions (e.g. mp_angel_city)
	// - Playing can start before their own, longer Prematch-based cutscene delay
	// finishes, and this 2.1s would otherwise hide the HUD early, mid-cutscene
	// (confirmed in-game on "За Баркером"). Only skipped when actually in Campaign -
	// see the comment above.
	if ( gameState == eGameState.Playing )
	{
		if ( GetCurrentPlaylistName() != CAMPAIGN || HudToggleMinimal_GetCampaignIntroDelay() == null )
			thread HudToggleMinimal_ApplyDelayedOnRoundStart()
		return
	}

	// Frontier Defense (COOPERATIVE): confirmed in-game that waiting for the real
	// eGameState.Postmatch (mp/_coobj_towerdefense.nut's own victory/defeat sequence
	// is supposed to end with an explicit SetGameState(eGameState.Postmatch)) does
	// NOT reliably show the HUD in practice - the person reported the results table
	// opens but the HUD still never comes back. Restored the eGameState.WinnerDetermined
	// branch: gameState reaches WinnerDetermined right when the match ends and stays
	// there client-side observably (client/cl_gamemode_coop.nut's own dev comment
	// calls this a known hack - COOP needs updating to use Epilogue/Postmatch
	// "properly"), so show as soon as the match is actually over
	// (Coop_IsGameOver(), from _gamemode_coop_shared.nut, only ever loaded
	// client-side in COOPERATIVE - GameMode_AddClientScript(COOPERATIVE,
	// "client/cl_gamemode_coop") in _settings.nut) rather than waiting on Postmatch,
	// which in practice doesn't reliably show the HUD at all.
	if ( gameState == eGameState.WinnerDetermined )
	{
		// 13s delay = _consts.nut's COOP_VICTORY_ANNOUNCEMENT_LENGTH /
		// COOP_DEFEAT_ANNOUNCEMENT_LENGTH (both 13.0) - mp/_coobj_towerdefense.nut's
		// own victory/defeat announcement length, so the HUD comes back right as
		// that finishes instead of immediately when the match ends.
		if ( GameRules.GetGameMode() == COOPERATIVE && Coop_IsGameOver() )
			thread HudToggleMinimal_ApplyDelayedOnCoopGameOver()
		return
	}

	if ( gameState < eGameState.Postmatch )
		return

	level.hudToggle_hidden = false
	HudToggleMinimal_Apply( false )
}

function HudToggleMinimal_ApplyDelayedOnRoundStart()
{
	wait 2.1
	HudToggleMinimal_Apply( level.hudToggle_hidden )
}

function HudToggleMinimal_ApplyDelayedOnCampaignIntro( delay )
{
	wait delay
	HudToggleMinimal_Apply( level.hudToggle_hidden )
}

function HudToggleMinimal_OnSpawnFlagChanged( player )
{
	if ( player != GetLocalClientPlayer() )
		return

	// only act when the flag just turned ON (the jump-in sequence - "прыжок в
	// расположение" - just started); hide 2.9s later, while still riding/jumping in
	// the dropship, before the player lands.
	// (HasCinematicFlag is server-only; client code checks the bitmask directly)
	if ( !( player.GetCinematicEventFlags() & CE_FLAG_CLASSIC_MP_SPAWNING ) )
		return

	thread HudToggleMinimal_ApplyDelayed( player )
}

function HudToggleMinimal_OnIntroFlagChanged( player )
{
	if ( player != GetLocalClientPlayer() )
		return

	// only act when the flag just turned ON
	if ( !( player.GetCinematicEventFlags() & CE_FLAG_INTRO ) )
		return

	// mp_wargames: hide 2.5s into the cutscene, not instantly. mp_npe ("CERTIFICATION"):
	// 2.0s into its pod intro. Other Campaign maps: still instant.
	if ( GetMapName() == "mp_wargames" )
		thread HudToggleMinimal_ApplyDelayedOnIntro( player, 2.5 )
	else if ( GetMapName() == "mp_npe" )
		thread HudToggleMinimal_ApplyDelayedOnIntro( player, 2.0 )
	else
		HudToggleMinimal_Apply( level.hudToggle_hidden )
}

function HudToggleMinimal_ApplyDelayedOnIntro( player, delay )
{
	player.EndSignal( "OnDestroy" )
	wait delay
	HudToggleMinimal_Apply( level.hudToggle_hidden )
}

function HudToggleMinimal_ApplyDelayed( player )
{
	player.EndSignal( "OnDestroy" )
	wait 2.9
	HudToggleMinimal_Apply( level.hudToggle_hidden )
}

function HudToggleMinimal_Apply( hidden )
{
	local localPlayer = GetLocalClientPlayer()
	if ( !IsValid( localPlayer ) )
		return

	localPlayer.ClientCommand( "cl_drawhud " + ( hidden ? "0" : "1" ) )
	localPlayer.ClientCommand( "crosshair " + ( hidden ? "0" : "1" ) )

	// togglehud is a native toggle - only send it on an actual state change,
	// otherwise a redundant call would flip it back by accident.
	if ( level.hudToggle_lastNativeState != hidden )
	{
		localPlayer.ClientCommand( "togglehud" )
		level.hudToggle_lastNativeState = hidden
	}
}
