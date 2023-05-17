
#include amxmodx
#include engine
#include fakemeta
#include sorting
#include reapi
#define CHARS_STEAMID 64
#define CHARS_NAME 64
/*#if !defined MAX_PLAYERS
	#define MAX_PLAYERS 32
#endif*/
// Раскомментить если нужны дебаг принты в чат
//#define USE_DEBUG_PRINTS

// Основные настройки плагина
new const filename_logs[] = 					"StrafeScanner.log"; // amxmodx/logs/%filename_logs% - файл логов
new const MAX_WARNS_HELPER = 					2; 		// максимальное кол-во варнов за strafe helper 
new const IN_SESSION_STRAFES = 					200; 	// максимум прыжков в session 
new const Float: MAX_PERCENT_IDEAL_FAST = 			77.0; 	// [Fast] (ban - за ~90 стрейфов)
new const Float: MAX_PERCENT_IDEAL_TOTAL = 			83.0; 	// [Total] (ban - за сессию)
new const Float: MAX_PERCENT_IDEAL_WITH_WARNS = 	69.0; 	// [Warns] (ban - за 3 варнов в сессии)

// для того чтобы плагин не работал в трейнинг режиме
native mixsystem_get_mode();
new training_mode = 0;

// для проверки
new bits_check_buttons = (IN_MOVELEFT | IN_MOVERIGHT | IN_FORWARD | IN_BACK);
new keys[4] = { IN_FORWARD, IN_MOVELEFT, IN_BACK, IN_MOVERIGHT };
new yaw = 1;
new menucolors[][] = { "\d", "\w", "\y", "\r" };
new const Float: check_color[5] = { 0.0 , 30.0 , 50.0 , 69.0 , 100.0 };
new const Float: check_sidemove[2] =   { -410.0 , 410.0 };
new const Float: check_ideal_switch[2] = { -200.0 , 200.0 };
new const Float: check_fast_session[2] = { 85.0 , 90.0 };
new const Float: check_last_autoupdate = 0.3;
enum { w, a, s, d };
enum { left, right };
enum { session, total };
enum { current, release }; // текущий, предыдущий
enum {
	sort_default,
	sort_only_alive,
	sort_by_only_ct_tt,
	sort_by_top5_ideal_total,
	sort_by_top5_ideal_session
};

new const c_viewmodes[][] =
{
	"default",
	"only alive",
	"only tt-ct",
	"top 5 ideal total",
	"top 5 ideal session"
};
new Float: f_last_autoupdate_menu;

enum _: e_stats_data
{
	s_steamid[64],
	s_nickname[636],
	Float: f_switch_ideal_percent_session,
	Float: f_switch_ideal_percent_total,
	Float: f_angles[3],
	Float: f_angles_old[3],
	Float: f_sidemove,
	Float: f_sidemove_old,
	Float: f_forwardmove,
	Float: f_forwardmove_old,
	bool: b_turning_left,
	bool: b_turning_right,
	buttons,
	buttons_old,
	buttons_clicking[4],
	buttons_old_strafecounter,
	buttons_pressed_count_session,
	buttons_pressed_count_total,
	player_flags,
	switch_ideal_session,
	switch_ideal_total,
	switch_default_session,
	switch_default_total,
	view_mode_stats,
	warnings_using_strafehelper,
	bool: b_banned
};
new g_eStats[33][e_stats_data];
new g_eStatsSorted[33][e_stats_data];

enum _: e_menu_data
{
	bool: b_menu_opened,
	menu_page,
	menu_players[MAX_PLAYERS],
	menu_opened_page
};
new g_eMenu[MAX_PLAYERS+1][e_menu_data];

public plugin_init()
{
	register_clcmd("say /str", "FunctionOpenStatsMenu", ADMIN_BAN);
	register_clcmd("say /strafe", "FunctionOpenStatsMenu", ADMIN_BAN);
	register_plugin("Strafe scanner", "1.5 fix", "Nicotine");
	register_forward(FM_CmdStart, "FM_CmdStart_Pre", false);
	register_menucmd(register_menuid("old_menu_strafe_stats"), 1023, "FunctionStatsMenuHandle");

	RegisterHookChain(RG_CBasePlayer_SetClientUserInfoName, "CBasePlayer_SetUserInfoName");// reapi
}

public CBasePlayer_SetUserInfoName(const id, buffer[], s_new_name[])
{
	if (is_user_connected(id)) {
		get_user_name(id, g_eStats[id][s_nickname], CHARS_NAME-1);
		get_user_name(id, g_eStatsSorted[id][s_nickname], CHARS_NAME-1);
	}
}

public client_putinserver(id)
{
	get_user_name(id, g_eStats[id][s_nickname], CHARS_NAME-1);
	get_user_name(id, g_eStatsSorted[id][s_nickname], CHARS_NAME-1);
	resetstats(id);
}

public client_disconnected(id)
{
	resetstats(id);
}

public resetstats(id)
{
	g_eMenu[id][b_menu_opened] = false;
	g_eMenu[id][menu_opened_page] = 0;

	g_eStats[id][b_banned] = false;
	g_eStats[id][b_turning_left] = false;
	g_eStats[id][b_turning_right] = false;
	g_eStats[id][warnings_using_strafehelper] = 0;
	
	g_eStats[id][buttons_pressed_count_session] = 0;
	g_eStats[id][switch_ideal_session] = 0;
	g_eStats[id][switch_default_session] = 0;
	g_eStats[id][f_switch_ideal_percent_session] = 0.0;
	
	g_eStats[id][buttons_pressed_count_total] = 0;
	g_eStats[id][switch_ideal_total] = 0;
	g_eStats[id][switch_default_total] = 0;
	g_eStats[id][f_switch_ideal_percent_total] = 0.0;
	
}

public FunctionAutoUpdateStats()
{
	new id;
	for (id = 1; id <= MaxClients; id++) {
		if ((get_gametime() - f_last_autoupdate_menu) < check_last_autoupdate)
			continue;
		if (!is_user_connected(id) || !g_eMenu[id][b_menu_opened] || is_user_bot(id))
			continue;
		FunctionStatsMenu(id, g_eMenu[id][menu_opened_page]);
	}
	f_last_autoupdate_menu = get_gametime();
	return PLUGIN_HANDLED;
}

public FM_CmdStart_Pre(id, uc_handle, seed)
{
	if (!is_user_alive(id) || g_eStats[id][b_banned] || mixsystem_get_mode() == training_mode)
	{
		return FMRES_IGNORED;
	}
	
	if (g_eStats[id][switch_default_session] >= IN_SESSION_STRAFES)
	{
		reset_session_stats(id);
	}
	get_uc(uc_handle, UC_ForwardMove, g_eStats[id][f_forwardmove]);
	get_uc(uc_handle, UC_SideMove, g_eStats[id][f_sidemove]);
	g_eStats[id][buttons] = pev(id, pev_button);
	g_eStats[id][buttons_old] = pev(id, pev_oldbuttons);
	g_eStats[id][player_flags] = pev(id, pev_flags);
	pev(id, pev_angles, g_eStats[id][f_angles]);
	
	if (g_eStats[id][f_angles_old][yaw] > g_eStats[id][f_angles][yaw])
	{
		g_eStats[id][b_turning_left] = false;
		g_eStats[id][b_turning_right] = true;
	}
	else if(g_eStats[id][f_angles_old][yaw] < g_eStats[id][f_angles][yaw])
	{
		g_eStats[id][b_turning_left] = true;
		g_eStats[id][b_turning_right] = false;
	} else {
		g_eStats[id][b_turning_left] = false;
		g_eStats[id][b_turning_right] = false;
	}
	
	if (g_eStats[id][player_flags] & FL_ONGROUND) // ignore on ground frames
	{
		if (g_eStats[id][buttons] & IN_JUMP && g_eStats[id][buttons_old] & ~IN_JUMP) {
			g_eStats[id][b_turning_left] = false;
			g_eStats[id][b_turning_right] = false;
		}
		return FMRES_IGNORED;
	}

	for (new button; button < sizeof keys; button++) {
		if (g_eStats[id][buttons] & keys[button] && g_eStats[id][buttons_old] & ~keys[button]) {
			g_eStats[id][buttons_clicking][button]++;
			g_eStats[id][buttons_pressed_count_session]++;
			g_eStats[id][buttons_pressed_count_total]++;
		}
	}
	
	// fix issue -%f random percent 0 : 0 = ? , e.t.c
	if (g_eStats[id][switch_default_session] > 0 && g_eStats[id][switch_ideal_session] > 0) {
		g_eStats[id][f_switch_ideal_percent_session] = get_ideal_percent_session(id);
	}
	if (g_eStats[id][switch_default_total] > 0 && g_eStats[id][switch_ideal_total] > 0) {
		g_eStats[id][f_switch_ideal_percent_total] = get_ideal_percent_total(id);
	}
	
	if ( check_sidemove[0] < g_eStats[id][f_sidemove] < check_sidemove[1])
	{
		if (check_ideal_switch_buttons(id))
		{
			if(g_eStats[id][switch_ideal_session] < g_eStats[id][switch_default_session])
			{
				++g_eStats[id][switch_ideal_session];
				++g_eStats[id][switch_ideal_total];
			}
			//FunctionAutoUpdateStats();
			//g_eStats[id][f_switch_ideal_percent_session] = float(g_eStats[id][switch_ideal_session]) / float(g_eStats[id][switch_default_session]) * 100.0;


			if (check_fast_session[0] < g_eStats[id][switch_default_session] < check_fast_session[1])
			{
				if (g_eStats[id][f_switch_ideal_percent_session] > MAX_PERCENT_IDEAL_FAST )
				{
					//PunishPlayer(id, "Cheating: [F]");
					UTIL_LogUser(id, fmt("Strafe helper (F - fast) info %d|%d (%.1f %%)", g_eStats[id][switch_ideal_session], g_eStats[id][switch_default_session], g_eStats[id][f_switch_ideal_percent_session] ));
				}
			}
			if (g_eStats[id][switch_default_session] >= IN_SESSION_STRAFES)
			{ 
				UTIL_LogUser(id, fmt("strafestats: %i/%i (%.1f %%)", g_eStats[id][switch_ideal_session], g_eStats[id][switch_default_session], g_eStats[id][f_switch_ideal_percent_session] ));
				#if defined USE_DEBUG_PRINTS
					for (new i = 0 ; i < 3 ; i++) // debug print
					{
						client_print_color(id,print_team_blue,"^1[^4TEST^1] ^4Strafe stats [%d/%d] %.2f %% ", g_eStats[id][switch_ideal_session] , g_eStats[id][switch_default_session], g_eStats[id][f_switch_ideal_percent_session]);
					}
				#endif
				if (g_eStats[id][f_switch_ideal_percent_session] > MAX_PERCENT_IDEAL_TOTAL )
				{
					//PunishPlayer(id, "Cheating: [T]");
					UTIL_LogUser(id, fmt("Strafe helper (T - total) info %d|%d (%.1f %%)",
					  g_eStats[id][switch_ideal_session], g_eStats[id][switch_default_session], g_eStats[id][f_switch_ideal_percent_session] ));
				}
				

				if (g_eStats[id][f_switch_ideal_percent_session] > MAX_PERCENT_IDEAL_WITH_WARNS )
				{
					if (++g_eStats[id][warnings_using_strafehelper] >= MAX_WARNS_HELPER)
					{
						//PunishPlayer(id, "Cheating: [W]");
						UTIL_LogUser(id, fmt("Strafe helper (W - Warnings) streak 3 info %d|%d (%.1f %%)",
						  g_eStats[id][switch_ideal_session], g_eStats[id][switch_default_session], g_eStats[id][f_switch_ideal_percent_session] ));
					}
				}
			}
		}
	}
	if (g_eStats[id][b_turning_left] || g_eStats[id][b_turning_right])
	{
		if ( func_strafechecking(id, IN_MOVELEFT,  IN_MOVERIGHT | IN_BACK      | IN_FORWARD)
		||   func_strafechecking(id, IN_MOVERIGHT, IN_MOVELEFT  | IN_BACK      | IN_FORWARD)
		||   func_strafechecking(id, IN_BACK,      IN_FORWARD   | IN_MOVERIGHT | IN_MOVELEFT)
		||   func_strafechecking(id, IN_FORWARD,   IN_BACK      | IN_MOVELEFT  | IN_MOVERIGHT))
		{
			calc_strafe_and_update_menu(id);
		}
	}
	
	if (check_bits_count((g_eStats[id][buttons] & bits_check_buttons), 2))
	{
		g_eStats[id][buttons_old_strafecounter] = 0;
	}
	else if (g_eStats[id][b_turning_left] || g_eStats[id][b_turning_right])
	{
		g_eStats[id][buttons_old_strafecounter] = g_eStats[id][buttons];
	}
	
	g_eStats[id][f_angles_old] = g_eStats[id][f_angles];
	g_eStats[id][f_sidemove_old] = g_eStats[id][f_sidemove]; 
	g_eStats[id][f_forwardmove_old] = g_eStats[id][f_forwardmove];
	return FMRES_IGNORED;
}

public calc_strafe_and_update_menu(id) {
	g_eStats[id][switch_default_session]++;
	g_eStats[id][switch_default_total]++;
	//FunctionAutoUpdateStats();
}

public reset_session_stats(id)
{
	g_eStats[id][buttons_pressed_count_session] = 0;
	g_eStats[id][switch_default_session] = 0;
	g_eStats[id][switch_ideal_session] = 0;
	g_eStats[id][f_switch_ideal_percent_session] = 0.0;
}

/*
public PunishPlayer(id, reason[])
{
	
	g_eStats[id][b_banned] = true;
	client_print_color(0, print_team_blue, "^1[^3Strafe scanner^1] ^3%s ^1detected ^4%s", g_eStats[id][s_nickname], reason);
	server_cmd("fb_ban 0 #%i ^"%s^"", get_user_userid(id), reason);
	server_cmd("kick #%i ^"%s^"", get_user_userid(id), reason);
	
}
*/

stock UTIL_LogUser(const id, const szCvar[], any:...) {
	static szLogFile[128];
	if (!szLogFile[0])
	{
		get_localinfo("amxx_logs", szLogFile, charsmax(szLogFile));
		format(szLogFile, charsmax(szLogFile), "/%s/%s", szLogFile, filename_logs);
	}
	new iFile;
	if ( (iFile = fopen(szLogFile, "a")) )
	{
		new message[128]; vformat(message, charsmax(message), szCvar, 3);
		new szIp[32]; get_user_ip(id, szIp, charsmax(szIp), 1);
		new szTime[22]; get_time("%d.%m.%Y - %H:%M:%S", szTime, charsmax(szTime));
		
		new wasd[64]; formatex(wasd,63,"total: [%i/i] | keys: [A:%i D:%i W:%i S:%i , all:%i]",
			g_eStats[id][switch_ideal_total], g_eStats[id][switch_default_total], g_eStats[id][buttons_clicking][a], g_eStats[id][buttons_clicking][d], g_eStats[id][buttons_clicking][w], g_eStats[id][buttons_clicking][s], g_eStats[id][buttons_pressed_count_total]);
		fprintf(iFile, "L [%s] %s , %s , %s : ^n              %s %s^n", szTime, g_eStats[id][s_nickname], g_eStats[id][s_steamid], szIp, message, wasd);
		fclose(iFile);
	}
}

public FunctionOpenStatsMenu(id, flags)
{
	if (get_user_flags(id) & flags) {
		FunctionStatsMenu(id);
	}
	return PLUGIN_HANDLED;
}


stock bool: get_continue_by_view_mode_stats(id, target)
{
	if     (g_eStats[id][view_mode_stats] == sort_default) 			return bool:(is_user_bot(target) || is_user_hltv(target))
	else if (g_eStats[id][view_mode_stats] == sort_only_alive) 			return bool:(is_user_bot(target) || is_user_hltv(target) || !is_user_alive(target));
	else if (g_eStats[id][view_mode_stats] == sort_by_only_ct_tt) 		return bool:(is_user_bot(target) || is_user_hltv(target) || (get_user_team(target) == 3));
	else if (g_eStats[id][view_mode_stats] == sort_by_top5_ideal_total) 	return bool:(is_user_bot(target) || is_user_hltv(target))
	else if (g_eStats[id][view_mode_stats] == sort_by_top5_ideal_session) 	return bool:(is_user_bot(target) || is_user_hltv(target))
	return false;
}
FunctionStatsMenu(id, page = 0)
{
	if (page < 0) {
		return PLUGIN_HANDLED;
	}
	g_eMenu[id][b_menu_opened] = true;
	g_eMenu[id][menu_opened_page] = page;
	new playersArray[32], playersNum, MenuText[MAX_MENU_LENGTH], target;
	new bool: b_SortingStats = ((g_eStats[id][view_mode_stats] == sort_by_top5_ideal_total) || (g_eStats[id][view_mode_stats] == sort_by_top5_ideal_session));
	if (b_SortingStats)
	{
		func_array_set_values();
		
		if (g_eStats[id][view_mode_stats] == sort_by_top5_ideal_total)
			SortCustom2D( g_eStatsSorted, 33, "MySortPercentsFunctionTotal");
		else if (g_eStats[id][view_mode_stats] == sort_by_top5_ideal_session)
			SortCustom2D( g_eStatsSorted, 33, "MySortPercentsFunctionSession");
		
		for (new i = 0; i < sizeof g_eStatsSorted; i++ ) {
			if (!is_user_connected(target) || get_continue_by_view_mode_stats(id, target))
				continue;
			playersArray[playersNum++] = target;
			if (playersNum >= 5) break;
		}
	}
	else {
		for (target = 1; target <= MaxClients; target++)
		{
			if (!is_user_connected(target) || get_continue_by_view_mode_stats(id, target)) {
				continue;
			}
			playersArray[playersNum++] = target;
		}
	}
	new keys = MENU_KEY_1|MENU_KEY_0;
	new i = min(page * 8, playersNum);
	new Start = i - (i % 8);
	new End = min(Start + 8, playersNum);

	page = Start / 8;

	g_eMenu[id][menu_players] = playersArray;
	g_eMenu[id][menu_page] = page;
	new maxstr = (((playersNum - 1) / 8) + 1);
	new len = formatex(MenuText, charsmax(MenuText), 	"\rStrafe scanner: \dstats (%d / %d)^n^n\
												\r1. \w[%s]^n",
												page + 1, maxstr, c_viewmodes[g_eStats[id][view_mode_stats]]);
	keys |= MENU_KEY_9;

	if (b_SortingStats)
	{
		for (i = Start; i < End; i++)
		{
			target = playersArray[i];
			new warns_info[12];

			formatex(warns_info, charsmax(warns_info)," ");
			if (g_eStatsSorted[target][warnings_using_strafehelper] > 0) {
				formatex(warns_info, charsmax(warns_info), " %s(%i w)",
					g_eStatsSorted[target][warnings_using_strafehelper] < 2 ? "\y" : "\r", g_eStatsSorted[target][warnings_using_strafehelper] );
			}
			
			new session_pcolor[3], total_pcolor[3];
			/*for(new i; i < 4; i++) {
				add(session_pcolor, 9, fmt("%s", (check_color[i] < g_eStatsSorted[target][f_switch_ideal_percent_session] <= check_color[i+1]) ? menucolors[i] : "" ));
				add(total_pcolor, 9, fmt("%s", (check_color[i] < g_eStatsSorted[target][f_switch_ideal_percent_total] <= check_color[i+1]) ? menucolors[i] : "" ));
			}*/
			
			formatex(session_pcolor, charsmax(session_pcolor),"%s%s%s%s",
				(check_color[0] < g_eStatsSorted[target][f_switch_ideal_percent_session] <= check_color[1]) ? "\d" : "",
				(check_color[1] < g_eStatsSorted[target][f_switch_ideal_percent_session] <= check_color[2]) ? "\w" : "",
				(check_color[2] < g_eStatsSorted[target][f_switch_ideal_percent_session] <= check_color[3]) ? "\y" : "",
				(check_color[3] < g_eStatsSorted[target][f_switch_ideal_percent_session] <= check_color[4]) ? "\r" : "");

			formatex(total_pcolor, charsmax(total_pcolor),"%s%s%s%s",
				(check_color[0] < g_eStatsSorted[target][f_switch_ideal_percent_total] <= check_color[1]) ? "\d" : "",
				(check_color[1] < g_eStatsSorted[target][f_switch_ideal_percent_total] <= check_color[2]) ? "\w" : "",
				(check_color[2] < g_eStatsSorted[target][f_switch_ideal_percent_total] <= check_color[3]) ? "\y" : "",
				(check_color[3] < g_eStatsSorted[target][f_switch_ideal_percent_total] <= check_color[4]) ? "\r" : "");
				
			
			new i_percent_session = floatround( g_eStatsSorted[target][f_switch_ideal_percent_session], floatround_round);
			new i_percent_total = floatround( g_eStatsSorted[target][f_switch_ideal_percent_total], floatround_round);
			
			len += formatex(MenuText[len], charsmax(MenuText)-len, "\w%s \d(\wS %i/%i\d,%s%i %%\d) (\wT %s%i %%\d)%s^n",
				g_eStatsSorted[target][s_nickname],
				g_eStatsSorted[target][switch_ideal_session], g_eStatsSorted[target][switch_default_session],
				(g_eStatsSorted[target][switch_default_session] > 15) ? session_pcolor : "\d", i_percent_session,
				(g_eStatsSorted[target][switch_default_total] > 15) ? total_pcolor : "\d",   i_percent_total,
				(g_eStatsSorted[target][warnings_using_strafehelper] > 0) ? warns_info : "" );
		}
	}
	else
	{
		for (i = Start; i < End; i++)
		{
			target = playersArray[i];
			new warns_info[12];

			formatex(warns_info, charsmax(warns_info)," ");
			if (g_eStats[target][warnings_using_strafehelper] > 0) {
				formatex(warns_info, charsmax(warns_info), " %s(%i w)",
					g_eStats[target][warnings_using_strafehelper] < 2 ? "\y" : "\r",
					g_eStats[target][warnings_using_strafehelper] );
			}
			new session_pcolor[3], total_pcolor[3];
			/*for(new i; i < 4; i++) {
				add(session_pcolor, 9, fmt("%s", (check_color[i] < g_eStats[target][f_switch_ideal_percent_session] <= check_color[i+1]) ? menucolors[i] : "" ));
				add(total_pcolor, 9, fmt("%s", (check_color[i] < g_eStats[target][f_switch_ideal_percent_total] <= check_color[i+1]) ? menucolors[i] : "" ));
			}*/
			formatex(session_pcolor, charsmax(session_pcolor),"%s%s%s%s",
				(check_color[0] < g_eStats[target][f_switch_ideal_percent_session] <= check_color[1]) ? "\d" : "",
				(check_color[1] < g_eStats[target][f_switch_ideal_percent_session] <= check_color[2]) ? "\w" : "",
				(check_color[2] < g_eStats[target][f_switch_ideal_percent_session] <= check_color[3]) ? "\y" : "",
				(check_color[3] < g_eStats[target][f_switch_ideal_percent_session] <= check_color[4]) ? "\r" : "");

			formatex(total_pcolor, charsmax(total_pcolor),"%s%s%s%s",
				(check_color[0] < g_eStats[target][f_switch_ideal_percent_total] <= check_color[1]) ? "\d" : "",
				(check_color[1] < g_eStats[target][f_switch_ideal_percent_total] <= check_color[2]) ? "\w" : "",
				(check_color[2] < g_eStats[target][f_switch_ideal_percent_total] <= check_color[3]) ? "\y" : "",
				(check_color[3] < g_eStats[target][f_switch_ideal_percent_total] <= check_color[4]) ? "\r" : "");
				
			new i_percent_session = floatround( g_eStats[target][f_switch_ideal_percent_session], floatround_round);
			new i_percent_total = floatround( g_eStats[target][f_switch_ideal_percent_total], floatround_round);
			
			len += formatex(MenuText[len], charsmax(MenuText)-len, "\w%s\d(\wS %i/%i\d,%s%i %%\d) (\wT %s%i %%\d)%s^n",
				g_eStats[target][s_nickname],
				g_eStats[target][switch_ideal_session], g_eStats[target][switch_default_session],
				(g_eStats[target][switch_default_session] > 15) ? session_pcolor : "\d", i_percent_session,
				(g_eStats[target][switch_default_total] > 15) ? total_pcolor : "\d",   i_percent_total,
				(g_eStats[target][warnings_using_strafehelper] > 0) ? warns_info : "" );
		}
	}
	
	if (End < playersNum) {
		formatex(MenuText[len], charsmax(MenuText) - len, "^n\r9. \wNext^n\r0. \w%s", page ? "Back" : "Exit");
		keys |= MENU_KEY_9;
	} else {
		formatex(MenuText[len], charsmax(MenuText) - len, "^n\r0. \w%s", page ? "Back" : "Exit");
	}
	
	show_menu(id, keys, MenuText, -1, "old_menu_strafe_stats");
	return PLUGIN_HANDLED;
}

public func_array_set_values()
{
	for (new i = 0; i < sizeof g_eStats; i++ )
	{
		g_eStatsSorted[i][f_switch_ideal_percent_session] =	g_eStats[i][f_switch_ideal_percent_session];
		g_eStatsSorted[i][f_switch_ideal_percent_total] = 	g_eStats[i][f_switch_ideal_percent_total];
		g_eStatsSorted[i][b_banned] = 				g_eStats[i][b_banned];
		for(new i; i < 3 ;i++) {
			g_eStatsSorted[i][f_angles][i] = 			g_eStats[i][f_angles][i];
			g_eStatsSorted[i][f_angles_old] = 			g_eStats[i][f_angles_old];
		}
		g_eStatsSorted[i][f_sidemove] = 				g_eStats[i][f_sidemove];
		g_eStatsSorted[i][f_sidemove_old] = 			g_eStats[i][f_sidemove_old];
		g_eStatsSorted[i][f_forwardmove] = 			g_eStats[i][f_forwardmove];
		g_eStatsSorted[i][f_forwardmove_old] = 			g_eStats[i][f_forwardmove_old];
		g_eStatsSorted[i][b_turning_left] = 				g_eStats[i][b_turning_left];
		g_eStatsSorted[i][b_turning_right] = 			g_eStats[i][b_turning_right];
		for(new i; i < 4 ;i++) {
			g_eStatsSorted[i][buttons_clicking][i] = 		g_eStats[i][buttons_clicking][i];
		}
		g_eStatsSorted[i][buttons_pressed_count_session] = 			g_eStats[i][buttons_pressed_count_session];
		g_eStatsSorted[i][buttons_pressed_count_total] = 			g_eStats[i][buttons_pressed_count_total];
		g_eStatsSorted[i][buttons] = 				g_eStats[i][buttons];
		g_eStatsSorted[i][buttons_old] = 				g_eStats[i][buttons_old];
		g_eStatsSorted[i][player_flags] = 				g_eStats[i][player_flags];
		g_eStatsSorted[i][switch_ideal_session] = 		g_eStats[i][switch_ideal_session];
		g_eStatsSorted[i][switch_ideal_total] = 			g_eStats[i][switch_ideal_total];
		g_eStatsSorted[i][switch_default_session] = 		g_eStats[i][switch_default_session];
		g_eStatsSorted[i][switch_default_total] = 		g_eStats[i][switch_default_total];
		g_eStatsSorted[i][buttons_old_strafecounter] = 	g_eStats[i][buttons_old_strafecounter];
		g_eStatsSorted[i][view_mode_stats] = 			g_eStats[i][view_mode_stats];
		g_eStatsSorted[i][warnings_using_strafehelper] = 	g_eStats[i][warnings_using_strafehelper];
	}
}

public MySortPercentsFunctionSession( e_stats_data: one[], e_stats_data: two[] ) {
	if( one[f_switch_ideal_percent_session] > two[f_switch_ideal_percent_session] )
		return -1;
	else if( one[f_switch_ideal_percent_session] < two[f_switch_ideal_percent_session] )
		return 1;
	return 0;
}

public MySortPercentsFunctionTotal( e_stats_data: one[], e_stats_data: two[] ) {
	if( one[f_switch_ideal_percent_total] > two[f_switch_ideal_percent_total] )
		return -1;
	else if( one[f_switch_ideal_percent_total] < two[f_switch_ideal_percent_total] )
		return 1;
	return 0;
}

public FunctionStatsMenuHandle(id, key)
{
	switch(key)
	{
		case 0: {
			SwitchViewFunctionStatsMenu(id);
		}
		
		case 8,9: {
			if(key == 9) {
				g_eMenu[id][b_menu_opened] = false;
			}
			FunctionStatsMenu(id, key == 8 ? ++g_eMenu[id][menu_page] : --g_eMenu[id][menu_page]);
		}
		
	}
	return PLUGIN_HANDLED;
}

SwitchViewFunctionStatsMenu(id)
{
	switch(g_eStats[id][view_mode_stats])
	{
		case sort_default: 				g_eStats[id][view_mode_stats] = sort_only_alive;
		case sort_only_alive: 			g_eStats[id][view_mode_stats] = sort_by_only_ct_tt;
		case sort_by_only_ct_tt: 			g_eStats[id][view_mode_stats] = sort_by_top5_ideal_total;
		case sort_by_top5_ideal_total: 	g_eStats[id][view_mode_stats] = sort_by_top5_ideal_session;
		case sort_by_top5_ideal_session: 	g_eStats[id][view_mode_stats] = sort_default;
	}
	client_print_color(id,print_team_blue,"^1[^3Strafe scanner^1] ^1view ^3strafe stats ^1changed on: ^4%s", c_viewmodes[g_eStats[id][view_mode_stats]])
	FunctionStatsMenu(id, g_eMenu[id][menu_opened_page]);
}

stock bool: check_bits_count(value, bit_max) {
	new count;
	while(count < bit_max) {
		count += (value & 1);
		value >>= 1;
	}
	if (count >= bit_max) {
		return true;
	}
	return false;
}

stock bool: check_ideal_switch_buttons(id)
{
	return bool: ((b_check_switch_in_frame(id, IN_MOVELEFT,   IN_MOVERIGHT) && g_eStats[id][f_sidemove]   == check_ideal_switch[0] )
		    || (b_check_switch_in_frame(id, IN_MOVERIGHT,  IN_MOVELEFT)  && g_eStats[id][f_sidemove]   == check_ideal_switch[1] )
		    || (b_check_switch_in_frame(id, IN_BACK,       IN_FORWARD)  && g_eStats[id][f_forwardmove] == check_ideal_switch[0] )
		    || (b_check_switch_in_frame(id, IN_FORWARD,   IN_BACK)      && g_eStats[id][f_forwardmove] == check_ideal_switch[1] )  );
}

stock bool: func_strafechecking(id, button, anotherbuttons) {
	return bool: (g_eStats[id][buttons_old_strafecounter] & ~button && g_eStats[id][buttons] & button && g_eStats[id][buttons] & ~anotherbuttons);
}
stock bool: b_check_switch_in_frame(id, button_current, button_release) {
	return bool:(g_eStats[id][buttons] & button_current && g_eStats[id][buttons_old] & button_release && g_eStats[id][buttons_old] & ~button_current);
}
stock bool: b_check_new_key(id, check_button) {
	return bool:(g_eStats[id][buttons] & check_button && g_eStats[id][buttons_old] & ~check_button)
}
stock Float: get_ideal_percent_session(id) {
	return Float:(float(g_eStats[id][switch_ideal_session]) / float(g_eStats[id][switch_default_session]) * 100.0);
}
stock Float: get_ideal_percent_total(id) {
	return Float:(float(g_eStats[id][switch_ideal_total]) / float(g_eStats[id][switch_default_total]) * 100.0);
}

#endscript

			/*formatex(session_pcolor, charsmax(session_pcolor),"%s%s%s%s",
				(check_color[0] < g_eStatsSorted[target][f_switch_ideal_percent_session] <= check_color[1]) ? "\d" : "",
				(check_color[1] < g_eStatsSorted[target][f_switch_ideal_percent_session] <= check_color[2]) ? "\w" : "",
				(check_color[2] < g_eStatsSorted[target][f_switch_ideal_percent_session] <= check_color[3]) ? "\y" : "",
				(check_color[3] < g_eStatsSorted[target][f_switch_ideal_percent_session] <= check_color[4]) ? "\r" : "");

			formatex(total_pcolor, charsmax(total_pcolor),"%s%s%s%s",
				(check_color[0] < g_eStatsSorted[target][f_switch_ideal_percent_total] <= check_color[1]) ? "\d" : "",
				(check_color[1] < g_eStatsSorted[target][f_switch_ideal_percent_total] <= check_color[2]) ? "\w" : "",
				(check_color[2] < g_eStatsSorted[target][f_switch_ideal_percent_total] <= check_color[3]) ? "\y" : "",
				(check_color[3] < g_eStatsSorted[target][f_switch_ideal_percent_total] <= check_color[4]) ? "\r" : "");
			*/