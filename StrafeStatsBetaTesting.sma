#include amxmodx
#include engine
#include fakemeta

#define CHARS_STEAMID 24
#define CHARS_NAME 32
 
// Раскомментить если нужны дебаг принты в чат
//#define USE_DEBUG_PRINTS

// для того чтобы плагин не работал в трейнинг режиме
native mixsystem_get_mode();

// Основные настройки плагина
new const MAX_SLOTS_OF_TOP = 5;						// максимальное кол-во игроков в меню статы (топ)
new const FILENAME_LOGS[] = "StrafeScanner.log";			// amxmodx/logs/%FILENAME_LOGS% - файл логов
new const MAX_WARNS_HELPER = 2;						// максимальное кол-во варнов за strafe helper 
new const IN_SESSION_STRAFES = 200;					// максимум прыжков в session 
new const Float: MAX_PERCENT_IDEAL_FAST = 77.0;			// [Fast] (ban - за ~90 стрейфов)
new const Float: MAX_PERCENT_IDEAL_TOTAL = 83.0;			// [Total] (ban - за сессию)
new const Float: MAX_PERCENT_IDEAL_WITH_WARNS = 69.0;	// [Warns] (ban - за 3 варнов в сессии)

new const c_keys[] = { IN_FORWARD, IN_MOVELEFT, IN_BACK, IN_MOVERIGHT };
new const menucolors[][] = { "\d", "\w", "\y", "\r" };
new const Float: check_color[5] = { -100.0 , 20.0 , 45.0 , 65.0 , 101.0 };
new const Float: check_sidemove[2] = { -410.0 , 410.0 };
new const Float: check_ideal_switch[2] = { -200.0 , 200.0 };
new const Float: check_fast_session[2] = { 85.0 , 90.0 };
new const Float: check_last_autoupdate = 0.1; // минимальное время в секундах от прошлого обновления статы
new const c_viewmodes[][] =
{
	"\wDefault",
	"\yOnly alive",
	"\wOnly \yTT\d|\rCT",
	"\rTop \yideal session",
	"\rTop \yideal total",
	"\rTOP \ywasd & buttons"
};

enum _: e_buttons { w, a, s, d };
enum { left, right };
enum { session, total };
enum { current, release };
enum {
	e_default,
	e_only_alive,
	e_only_ct_tt,
	e_top_session,
	e_top_total,
	e_top_pressed,
};

enum _: e_menu_data {
	bool: b_menu_opened,
	menu_page,
	menu_opened_page
};
new g_eMenu[33][e_menu_data];

enum _: e_stats_data {
	player_index,
	Float: f_ideal_session,
	Float: f_ideal_total,
	Float: f_sidemove,
	Float: f_sidemove_old,
	Float: f_forwardmove,
	Float: f_forwardmove_old,
	Float: f_angles[3],
	Float: f_angles_old[3],
	Float: f_menu_update,
	bool: b_strafe_in_left,
	bool: b_strafe_in_right,
	bool: b_banned,
	key_now,
	key_old,
	buttons_clicking_total[e_buttons],
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
	s_steamid[CHARS_STEAMID]
};
new g_eStats[33][e_stats_data];
new g_eSort[33][e_stats_data];

public plugin_init()
{
	register_clcmd("say /str", "func_open_stats_menu", ADMIN_BAN);
	register_clcmd("say /strafe", "func_open_stats_menu", ADMIN_BAN);
	register_plugin("Strafe scanner", "1.5 fix", "Nicotine");
	register_forward(FM_CmdStart, "func_fakemeta_prethink", false);
	register_menucmd(register_menuid("func_stats_menu_handle"), 1023, "func_stats_menu_mainHandle");
}

public client_putinserver(id)
{
	new temp_steamid[CHARS_STEAMID]; get_user_authid(id, temp_steamid, CHARS_STEAMID-1);
	if ( !equal( temp_steamid, g_eStats[id][s_steamid] ) ) {
		get_user_authid(id, g_eStats[id][s_steamid], CHARS_STEAMID-1);
	}
	g_eStats[id][player_index] = id;
	resetstats(id);
}

public client_disconnected(id)
{
	g_eStats[id][player_index] = 0;
	resetstats(id);
}

public func_auto_update_stats() {
	new players[32], pnum, id; get_players(players, pnum, "ch");
	for ( new AUTO; AUTO < pnum; AUTO++ )
	{
		id = players[AUTO];
		if (!g_eMenu[id][b_menu_opened] || (get_gametime() - g_eStats[id][f_menu_update]) < check_last_autoupdate) continue;
		func_stats_menu_main(id, g_eMenu[id][menu_opened_page]);
		g_eStats[id][f_menu_update] = get_gametime();
	}
	return PLUGIN_HANDLED;
}

public func_fakemeta_prethink(id, uc_handle, seed)
{
	if (!is_user_alive(id) || g_eStats[id][b_banned] /*|| mixsystem_get_mode() == 0*/) {
		return FMRES_IGNORED;
	}
	
	get_uc(uc_handle, UC_ForwardMove, g_eStats[id][f_forwardmove]);
	get_uc(uc_handle, UC_SideMove, g_eStats[id][f_sidemove]);
	g_eStats[id][key_now] = get_uc(uc_handle, UC_Buttons);
	g_eStats[id][key_old] = pev(id, pev_oldbuttons);
	g_eStats[id][player_flags] = pev(id, pev_flags);
	pev(id, pev_angles, g_eStats[id][f_angles]);
	
	if(g_eStats[id][f_angles_old][1] < g_eStats[id][f_angles][1]) {
		g_eStats[id][b_strafe_in_left] = true;
		g_eStats[id][b_strafe_in_left] = false;
	} else if (g_eStats[id][f_angles_old][1] > g_eStats[id][f_angles][1]) {
		g_eStats[id][b_strafe_in_left] = false;
		g_eStats[id][b_strafe_in_left] = true;
	} else {
		g_eStats[id][b_strafe_in_left] = g_eStats[id][b_strafe_in_left] = false;
	}

	if (g_eStats[id][player_flags] & FL_ONGROUND) {
		if (b_check_new_key(id, IN_JUMP)) {
			g_eStats[id][b_strafe_in_left] = false;
			g_eStats[id][b_strafe_in_left] = false;
		}
		return FMRES_IGNORED;
	}
	
	for (new ikey; ikey < sizeof c_keys; ikey++) {
		if ( b_check_new_key(id, c_keys[ikey]) ) {
			g_eStats[id][buttons_clicking_total][ikey]++;
			g_eStats[id][buttons_pressed_count_session]++;
			g_eStats[id][buttons_pressed_count_total]++;
		}
	}
	 
	get_percents_of_ideal_switch(id);
	//client_print_color(id, print_team_blue, "get_ideal_percent_total %.2f", g_eStats[id][f_ideal_total] );
	
	if ( check_sidemove[0] < g_eStats[id][f_sidemove] < check_sidemove[1])
	{
		if (check_ideal_switch_buttons(id))
		{
			++g_eStats[id][switch_ideal_session];
			++g_eStats[id][switch_ideal_total];
			
			//client_print_color(id, print_team_red, "+ ideal switch '%n' ", id);
			func_auto_update_stats();
			
			if (check_fast_session[0] < g_eStats[id][switch_default_session] < check_fast_session[1])
			{
				if (g_eStats[id][f_ideal_session] > MAX_PERCENT_IDEAL_FAST )
				{
					//PunishPlayer(id, "Cheating: [F]");
					func_create_logs(id, fmt("Strafe helper (F - fast) info %d|%d (%.1f %%)", g_eStats[id][switch_ideal_session], g_eStats[id][switch_default_session], g_eStats[id][f_ideal_session] ));
				}
			}
			if (g_eStats[id][switch_default_session] >= IN_SESSION_STRAFES)
			{ 
				func_create_logs(id, fmt("strafestats: %i/%i (%.1f %%)", g_eStats[id][switch_ideal_session], g_eStats[id][switch_default_session], g_eStats[id][f_ideal_session] ));
				#if defined USE_DEBUG_PRINTS
					for (new i = 0 ; i < 3 ; i++)
					{
						client_print_color(id,print_team_blue,"^1[^4TEST^1] ^4Strafe stats [%d/%d] %.2f %% ", g_eStats[id][switch_ideal_session] , g_eStats[id][switch_default_session], g_eStats[id][f_ideal_session]);
					}
				#endif
				if (g_eStats[id][f_ideal_session] > MAX_PERCENT_IDEAL_TOTAL )
				{
					//PunishPlayer(id, "Cheating: [T]");
					func_create_logs(id, fmt("Strafe helper (T - total) info %d|%d (%.1f %%)",
					  g_eStats[id][switch_ideal_session], g_eStats[id][switch_default_session], g_eStats[id][f_ideal_session] ));
				}
				
				if (g_eStats[id][f_ideal_session] > MAX_PERCENT_IDEAL_WITH_WARNS )
				{
					if (++g_eStats[id][warnings_using_strafehelper] >= MAX_WARNS_HELPER)
					{
						//PunishPlayer(id, "Cheating: [W]");
						func_create_logs(id, fmt("Strafe helper (W - Warnings) streak 3 info %d|%d (%.1f %%)",
						  g_eStats[id][switch_ideal_session], g_eStats[id][switch_default_session], g_eStats[id][f_ideal_session] ));
					}
				}
			}
		}
	}
	/*
	if (g_eStats[id][b_strafe_in_left] || g_eStats[id][b_strafe_in_left])
	{
		if (	get_default_button_pressing(id, IN_MOVELEFT, 		IN_FORWARD, IN_MOVERIGHT, 	IN_BACK)
		||	get_default_button_pressing(id, IN_MOVERIGHT, 		IN_FORWARD, IN_MOVELEFT, 	IN_BACK)
		||	get_default_button_pressing(id, IN_BACK, 			IN_FORWARD, IN_MOVERIGHT, 	IN_MOVELEFT)
		||	get_default_button_pressing(id, IN_FORWARD, 		IN_MOVELEFT, IN_MOVERIGHT, 	IN_BACK) )
		{
			g_eStats[id][switch_default_session]++;
			g_eStats[id][switch_default_total]++;
			func_auto_update_stats();
		}
	}
	*/
	if (g_eStats[id][b_strafe_in_left] || g_eStats[id][b_strafe_in_left])
	{
		// Reducing the number of lines of code with a loop and an array
		new const combos[][4] = { {IN_MOVELEFT, IN_FORWARD, IN_MOVERIGHT, IN_BACK},
							   {IN_MOVERIGHT, IN_FORWARD, IN_MOVELEFT, IN_BACK},
							   {IN_BACK, IN_FORWARD, IN_MOVERIGHT, IN_MOVELEFT},
							   {IN_FORWARD, IN_MOVELEFT, IN_MOVERIGHT, IN_BACK} };
		for (new i = 0; i < sizeof(combos); i++) {
			if (get_default_button_pressing(id, combos[i][0], combos[i][1], combos[i][2], combos[i][3])) {
				g_eStats[id][switch_default_session]++;
				g_eStats[id][switch_default_total]++;
				func_auto_update_stats();
				break;
			}
		}
	}
	
	/*
	if ((g_eStats[id][key_now] & IN_MOVERIGHT && (g_eStats[id][key_now] & IN_MOVELEFT || g_eStats[id][key_now] & IN_FORWARD || g_eStats[id][key_now] & IN_BACK))
	|| ((g_eStats[id][key_now] & IN_MOVELEFT && (g_eStats[id][key_now] & IN_FORWARD || g_eStats[id][key_now] & IN_BACK || g_eStats[id][key_now] & IN_MOVERIGHT)))
	|| ((g_eStats[id][key_now] & IN_FORWARD && (g_eStats[id][key_now] & IN_BACK || g_eStats[id][key_now] & IN_MOVERIGHT || g_eStats[id][key_now] & IN_MOVELEFT)))
	|| ((g_eStats[id][key_now] & IN_BACK && (g_eStats[id][key_now] & IN_MOVERIGHT || g_eStats[id][key_now] & IN_MOVELEFT || g_eStats[id][key_now] & IN_FORWARD))))
	{
		g_eStats[id][buttons_old_strafecounter] = 0;
	} else if(g_eStats[id][b_strafe_in_left] || g_eStats[id][b_strafe_in_left]) {
		g_eStats[id][buttons_old_strafecounter] = g_eStats[id][key_now];
	}
	
	*/
	if ((g_eStats[id][key_now] & (IN_MOVERIGHT | IN_MOVELEFT | IN_FORWARD | IN_BACK))
	&& ((g_eStats[id][key_now] & IN_MOVERIGHT) == 0 || (g_eStats[id][key_now] & IN_MOVELEFT) == 0
		|| (g_eStats[id][key_now] & IN_FORWARD) == 0 || (g_eStats[id][key_now] & IN_BACK) == 0)) {
		g_eStats[id][buttons_old_strafecounter] = 0;
	} else if(g_eStats[id][b_strafe_in_left] || g_eStats[id][b_strafe_in_left]) {
		g_eStats[id][buttons_old_strafecounter] = g_eStats[id][key_now];
	}
	if (g_eStats[id][switch_default_session] >= IN_SESSION_STRAFES) {
		reset_session_stats(id);
	}
	g_eStats[id][f_angles_old] = g_eStats[id][f_angles];
	g_eStats[id][f_sidemove_old] = g_eStats[id][f_sidemove]; 
	g_eStats[id][f_forwardmove_old] = g_eStats[id][f_forwardmove];
	return FMRES_IGNORED;
}

/*
public PunishPlayer(id, reason[])
{
	
	g_eStats[id][b_banned] = true;
	client_print_color(0, print_team_blue, "^1[^3Strafe scanner^1] ^3%n ^1detected ^4%s", id, reason);
	server_cmd("fb_ban 0 #%i ^"%s^"", get_user_userid(id), reason);
	server_cmd("kick #%i ^"%s^"", get_user_userid(id), reason);
	
}
*/

public func_open_stats_menu(id, flags)
{
	if (get_user_flags(id) & flags) {
		func_stats_menu_main(id);
	}
	return PLUGIN_HANDLED;
}

func_stats_menu_main(id, page = 0)
{
	if (page < 0) {
		return PLUGIN_HANDLED;
	}
	new bool: b_viewmode, keys, target, playersNum, playersArray[32], MenuText[512], ch_menu = charsmax(MenuText);
	g_eMenu[id][b_menu_opened] = true;
	g_eMenu[id][menu_opened_page] = page;
	keys = MENU_KEY_1 | MENU_KEY_0;
	
	switch (g_eStats[id][view_mode_stats]) {
		case e_top_total, e_top_session, e_top_pressed: b_viewmode = true;
		default: b_viewmode = false;
	}
	
	if (b_viewmode == true)
	{
		/* set values main-array by temp-array */
		new players[32], pnum, pid;
		get_players(players, pnum, "ch");
		for ( new i; i < pnum; i++ )
		{
			//Save a tempid so we do not re-index
			pid = players[i];
			// main order sort index player with percent stats
			// data sorting and by index do stats (0..32)
			g_eSort[pid][player_index] = g_eStats[pid][player_index];
			switch (g_eStats[id][view_mode_stats]) {
				case e_top_total: g_eSort[pid][f_ideal_total] = g_eStats[pid][f_ideal_total];
				case e_top_session: g_eSort[pid][f_ideal_session] = g_eStats[pid][f_ideal_session];
				case e_top_pressed: g_eSort[pid][buttons_pressed_count_total] = g_eStats[pid][buttons_pressed_count_total];
			}
		}
		/* sorting temp-array by g_eStats[id][view_mode_stats] */
		switch (g_eStats[id][view_mode_stats]) {
			case e_top_total: SortCustom2D( g_eSort, 33, "func_sort_by_percent_total");
			case e_top_session: SortCustom2D( g_eSort, 33, "func_sort_by_percent_session");
			case e_top_pressed: SortCustom2D( g_eSort, 33, "func_sort_by_pressed_keys");
		}
	}
	new players[32], pnum; get_players(players, pnum, "ch");
	for ( new i; i < pnum; i++ ) {
		playersArray[playersNum++] = players[i]; // create list players
		if (b_viewmode == true && playersNum >= MAX_SLOTS_OF_TOP)
			break;
	}
	
	new i = min(page * 7, playersNum);
	new Start = i - (i % 7);
	new End = min(Start + 7, playersNum);
	page = Start / 7;
	g_eMenu[id][menu_page] = page;
	new maxstr = (((playersNum - 1) / 7) + 1);
	new stats = g_eStats[id][view_mode_stats];
	
	new sz_pages_info[20], sz_first_string[20];
	format(sz_pages_info, charsmax(sz_pages_info), "\d(\w%i\d/\w%i\d)", page+1, maxstr )
	format(sz_first_string, charsmax(sz_first_string), "\r1.\w Sorted: %s", c_viewmodes[stats] );
	new len = formatex(MenuText, ch_menu, "\rStrafe scanner %s^n^n%s^n^n", sz_pages_info, sz_first_string );
	for (i = Start; i < End; i++)
	{
		if (playersArray[i] == 0)
			continue;
		target = (b_viewmode) ? g_eSort[ playersArray[i] ][player_index] : playersArray[i];
		// sorting for menu if bool: b_viewmode == true
		
		new warns_info[12], session_pcolor[3], total_pcolor[3];
		if (g_eStats[target][warnings_using_strafehelper] > 0)
		{
			formatex(warns_info, charsmax(warns_info), " %s(%i w)",
			g_eStats[target][warnings_using_strafehelper] < 2 ? "\y" : "\r",
			g_eStats[target][warnings_using_strafehelper] );
		}
		for(new e = 0; e < 4; e++) {
			add(session_pcolor, 2, fmt("%s", (check_color[e] < g_eStats[target][f_ideal_session] <= check_color[e+1]) ? menucolors[e] : "" ));
			add(total_pcolor, 2, fmt("%s", (check_color[e] < g_eStats[target][f_ideal_total] <= check_color[e+1]) ? menucolors[e] : "" ));
		}
		switch (g_eStats[id][view_mode_stats]) {
			case e_top_session:
			{
				len += add(MenuText, ch_menu, 	fmt("\w%n \d(\wS %s/%s\d,%s%i %s\d) %s^n",
					target,
					get_correct_string(g_eStats[target][switch_ideal_session]),
					get_correct_string(g_eStats[target][switch_default_session]),
					(g_eStats[target][switch_default_session] > 15) ? session_pcolor : "\d",
					floatround(g_eStats[target][f_ideal_session], floatround_round), "%",
					(g_eStats[target][warnings_using_strafehelper] > 0) ? warns_info : "" ) );
			}
			case e_top_total:
			{
				len += add(MenuText, ch_menu, fmt("\w%n \d(\wT %s/%s\d,%s%i %s\d)%s^n",
					target,
					get_correct_string(g_eStats[target][switch_ideal_total]),
					get_correct_string(g_eStats[target][switch_default_total]),
					(g_eStats[target][switch_default_total] > 15) ? total_pcolor : "\d",
					floatround(g_eStats[target][f_ideal_total], floatround_round), "%",
					(g_eStats[target][warnings_using_strafehelper] > 0) ? warns_info : "" ) );
			}
			case e_top_pressed:
			{
				len += add(MenuText, ch_menu, fmt("\w%n \d[ ", target));
				for(new i_key; i_key < 4; i_key++)
					add(MenuText, ch_menu, fmt("\y%s ", get_correct_string(g_eStats[target][buttons_clicking_total][i_key]) ) );
				add(MenuText, ch_menu, fmt("\d] [\wT:\y%s\d]^n", get_correct_string(g_eStats[target][buttons_pressed_count_total]) ) );
			}
			default:
			{
				len += add(MenuText, ch_menu, fmt("\w%n \d(\wS %s/%s\d,%s%.1f %s\d) (\wT %s%.1f %s\d)%s^n",
					target,
					get_correct_string(g_eStats[target][switch_ideal_session]),
					get_correct_string(g_eStats[target][switch_default_session]),
					(g_eStats[target][switch_default_session] > 15) ? session_pcolor : "\d", g_eStats[target][f_ideal_session], "%",
					(g_eStats[target][switch_default_total] > 15) ? total_pcolor : "\d",   g_eStats[target][f_ideal_total], "%",
					(g_eStats[target][warnings_using_strafehelper] > 0) ? warns_info : "" ) );
			}
		}
	}
	if (End < playersNum && !b_viewmode) {
		add(MenuText, ch_menu, fmt("^n\r9. \wNext^n\r0. \w%s", page ? "Back" : "Exit" ) );
		keys |= MENU_KEY_9;
	} else {
		add(MenuText, ch_menu, fmt("^n\r0. \w%s", page ? "Back" : "Exit" ) );
	}
	show_menu(id, keys, MenuText, -1, "func_stats_menu_handle");
	return PLUGIN_HANDLED;
}

public func_sort_by_percent_session (one[], two[]) {
	if (one[f_ideal_session] > two[f_ideal_session]) return -1;
	return (one[f_ideal_session] < two[f_ideal_session]) ? 1 : 0;
}

public func_sort_by_percent_total (one[], two[]) {
	if (one[f_ideal_total] > two[f_ideal_total]) return -1;
	return (one[f_ideal_total] < two[f_ideal_total]) ? 1 : 0;
}
public func_sort_by_pressed_keys (one[], two[]) {
	if (one[buttons_pressed_count_total] > two[buttons_pressed_count_total]) return -1;
	return (one[buttons_pressed_count_total] < two[buttons_pressed_count_total]) ? 1 : 0;
}

public func_stats_menu_mainHandle(id, key)
{
	switch(key) {
		case 0 : SwitchViewfunc_stats_menu_main(id);
		case 8,9 : {
			if(key == 9) g_eMenu[id][b_menu_opened] = false;
			func_stats_menu_main(id, key == 8 ? ++g_eMenu[id][menu_page] : --g_eMenu[id][menu_page]);
		}
		
	}
	return PLUGIN_HANDLED;
}

public SwitchViewfunc_stats_menu_main(id)
{
	switch (g_eStats[id][view_mode_stats]) {
		case e_default : 		g_eStats[id][view_mode_stats] = e_only_alive;
		case e_only_alive : 	g_eStats[id][view_mode_stats] = e_only_ct_tt;
		case e_only_ct_tt : 	g_eStats[id][view_mode_stats] = e_top_session;
		case e_top_session : 	g_eStats[id][view_mode_stats] = e_top_total;
		case e_top_total : 		g_eStats[id][view_mode_stats] = e_top_pressed;
		case e_top_pressed : 	g_eStats[id][view_mode_stats] = e_default;
	}
	client_print_color(id, print_team_blue, "^1[^3Strafe scanner^1] ^1sorting ^3statistic ^1changed on: ^4%s",
		get_clear_string(c_viewmodes[ g_eStats[id][view_mode_stats] ]) );
	func_stats_menu_main(id, g_eMenu[id][menu_opened_page]);
}

public reset_session_stats(id)
{
	g_eStats[id][buttons_pressed_count_session] = 0;
	g_eStats[id][switch_default_session] = 0;
	g_eStats[id][switch_ideal_session] = 0;
	g_eStats[id][f_ideal_session] = 0.0;
}

public resetstats(id)
{
	g_eStats[id][f_menu_update] = 0.0;
	g_eMenu[id][b_menu_opened] = false;
	g_eMenu[id][menu_opened_page] = 0;

	g_eStats[id][b_banned] = false;
	g_eStats[id][b_strafe_in_left] = false;
	g_eStats[id][b_strafe_in_right] = false;
	g_eStats[id][warnings_using_strafehelper] = 0;
	
	g_eStats[id][buttons_pressed_count_session] = 0;
	g_eStats[id][switch_ideal_session] = 0;
	g_eStats[id][switch_default_session] = 0;
	g_eStats[id][f_ideal_session] = 0.0;
	
	new temp_steamid[CHARS_STEAMID];
	get_user_authid(id, temp_steamid, CHARS_STEAMID-1);
	
	if ( !equal( temp_steamid, g_eStats[id][s_steamid] ) )
	{
		get_user_authid(id, g_eStats[id][s_steamid], CHARS_STEAMID-1);
		g_eStats[id][buttons_pressed_count_total] = 0;
		g_eStats[id][switch_ideal_total] = 0;
		g_eStats[id][switch_default_total] = 0;
		g_eStats[id][f_ideal_total] = 0.0;
	}
}

stock func_create_logs(const id, const szCvar[], any:...) {
	static szLogFile[128], iFile;
	if (!szLogFile[0])
	{
		get_localinfo("amxx_logs", szLogFile, charsmax(szLogFile));
		format(szLogFile, charsmax(szLogFile), "/%s/%s", szLogFile, FILENAME_LOGS);
	}
	if ( (iFile = fopen(szLogFile, "a")) )
	{
		new message[128]; vformat(message, charsmax(message), szCvar, 3);
		new szIp[32]; get_user_ip(id, szIp, charsmax(szIp), 1);
		new szTime[22]; get_time("%d.%m.%Y - %H:%M:%S", szTime, charsmax(szTime));
		
		new wasd[64]; formatex(wasd,63,"total: [%s | s] | keys AD|WS: [%s %s %s %s | all: %s]",
			get_correct_string(g_eStats[id][switch_ideal_total]), get_correct_string(g_eStats[id][switch_default_total]),
			get_correct_string(g_eStats[id][buttons_clicking_total][a]), get_correct_string(g_eStats[id][buttons_clicking_total][d]),
			get_correct_string(g_eStats[id][buttons_clicking_total][w]), get_correct_string(g_eStats[id][buttons_clicking_total][s]),
			get_correct_string(g_eStats[id][buttons_pressed_count_total]) );
		fprintf(iFile, "L [%s] %n , %s , %s : ^n              %s %s^n", szTime, id, g_eStats[id][s_steamid], szIp, message, wasd);
		fclose(iFile);
	}
}

stock bool: check_ideal_switch_buttons(id)
{
	return bool: (	(b_check_switch_in_frame(id, IN_MOVELEFT, IN_MOVERIGHT) && g_eStats[id][f_sidemove] == check_ideal_switch[0])
			||	(b_check_switch_in_frame(id, IN_MOVERIGHT, IN_MOVELEFT) && g_eStats[id][f_sidemove] == check_ideal_switch[1])
			||	(b_check_switch_in_frame(id, IN_BACK, IN_FORWARD) && g_eStats[id][f_forwardmove] == check_ideal_switch[0])
			||	(b_check_switch_in_frame(id, IN_FORWARD, IN_BACK) && g_eStats[id][f_forwardmove] == check_ideal_switch[1]) )
}

stock bool: b_check_switch_in_frame(id, button_current, button_release)
	return bool: (g_eStats[id][key_old] & button_release && b_check_new_key(id, button_current) )

stock bool: b_check_new_key(id, check_button)
	return bool: (g_eStats[id][key_now] & check_button && !(g_eStats[id][key_old] & check_button))

stock Float: get_ideal_percent_session(id)
	return Float: (float(g_eStats[id][switch_ideal_session]) / float(g_eStats[id][switch_default_session]) * 100.0);

stock Float: get_ideal_percent_total(id)
	return Float: (float(g_eStats[id][switch_ideal_total]) / float(g_eStats[id][switch_default_total]) * 100.0);

stock get_percents_of_ideal_switch(id)
{
	if (g_eStats[id][switch_default_session] > 0) {
		g_eStats[id][f_ideal_session] = get_ideal_percent_session(id);
	}
	if (g_eStats[id][switch_default_total] > 0) {
		g_eStats[id][f_ideal_total] = get_ideal_percent_total(id);
	}
}
/*
stock bool: get_default_button_pressing(id, key_check, key_ex1, key_ex2, key_ex3)
{
	return bool: (g_eStats[id][key_now] & key_check
			&& !(g_eStats[id][buttons_old_strafecounter] & key_check)
			&& !(g_eStats[id][key_now] & key_ex1)
			&& !(g_eStats[id][key_now] & key_ex2)
			&& !(g_eStats[id][key_now] & key_ex3) )
}
*/

stock bool: get_default_button_pressing(id, key_check, key_ex1, key_ex2, key_ex3) {
	// Simplifying a condition using the && operator and the testbits function
	return bool: ( testbits( g_eStats[id][key_now], key_check ) 
			&& !testbits( g_eStats[id][buttons_old_strafecounter], key_check )
			&& !testbits( g_eStats[id][key_now], key_ex1 | key_ex2 | key_ex3) );
}
stock bool: get_continue_by_view_mode_stats(id, target)
{
	switch (g_eStats[id][view_mode_stats]) {
		case 1: return bool: (is_user_bot(target) || is_user_hltv(target) || !is_user_alive(target) );
		case 2: return bool: (is_user_bot(target) || is_user_hltv(target) || (get_user_team(target) == 3) );
		case 0,3,4,5: return bool: (is_user_bot(target) || is_user_hltv(target) );
	}
	return false;
}

stock get_correct_string(intValue) {
	new corrected_string[10];
	if (intValue < 1000)
		format(corrected_string, 9, "%i", intValue ); 		// 553 = "553" 
	else
		format(corrected_string, 9, "%.3f K", (float(intValue) / 1000.0) );	// 12345 = "12.345 K"
	return corrected_string;
}

stock get_clear_string( format_string[] ) {
	new sz_clear_string[32];
	copy(sz_clear_string, 31, format_string);
	for(new i; i < sizeof menucolors; i++) {
		replace(sz_clear_string, 31, menucolors[i], "");
	}
	return sz_clear_string;
}

#endscript
