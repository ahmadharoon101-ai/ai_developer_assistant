import 'package:flutter/material.dart';

class NavItem {
  const NavItem(this.label, this.icon, this.path);
  final String label;
  final IconData icon;
  final String path;
}

const navItems = <NavItem>[
  NavItem('Dashboard', Icons.space_dashboard_outlined, '/dashboard'),
  NavItem('AI Chat', Icons.forum_outlined, '/chat'),
  NavItem('Projects', Icons.folder_copy_outlined, '/projects'),
  NavItem('Code Analyzer', Icons.manage_search, '/analyzer'),
  NavItem('Debugger', Icons.bug_report_outlined, '/debugger'),
  NavItem('Code Generator', Icons.code, '/generator'),
  NavItem('Test Generator', Icons.fact_check_outlined, '/tests'),
  NavItem('Documentation', Icons.description_outlined, '/docs'),
  NavItem('GitHub', Icons.hub_outlined, '/github'),
  NavItem('AI Agent', Icons.route_outlined, '/agent'),
  NavItem('Settings', Icons.settings_outlined, '/settings'),
];
