<?php
/**
 * phpMyAdmin configuration for single MariaDB node
 */

// Disable arbitrary server connections since we're providing predefined server
$cfg['AllowArbitraryServer'] = false;

// Server 1: Direct connection to MariaDB node
$cfg['Servers'][1]['auth_type'] = 'cookie';
$cfg['Servers'][1]['host'] = 'mariadb';
$cfg['Servers'][1]['port'] = 3306;
$cfg['Servers'][1]['verbose'] = 'MariaDB Single Node';
$cfg['Servers'][1]['compress'] = false;
$cfg['Servers'][1]['AllowNoPassword'] = false;

// General phpMyAdmin settings
$cfg['LoginCookieValidity'] = 3600;
$cfg['DefaultLang'] = 'en';
$cfg['ServerDefault'] = 1; // Default to the single MariaDB node
$cfg['UploadDir'] = '';
$cfg['SaveDir'] = '';
$cfg['TempDir'] = '/tmp/';

// Security settings
$cfg['blowfish_secret'] = 'single-mariadb-phpmyadmin-secret-key-32chars';
?>
