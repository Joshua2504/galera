<?php
/**
 * phpMyAdmin configuration for Galera cluster
 * This file provides a dropdown to select which node to connect to
 */

// Disable arbitrary server connections since we're providing predefined servers
$cfg['AllowArbitraryServer'] = false;

// Server 1: Galera Node 1 (Primary/Bootstrap)
$cfg['Servers'][1]['auth_type'] = 'cookie';
$cfg['Servers'][1]['host'] = 'galera-node1';
$cfg['Servers'][1]['port'] = 3306;
$cfg['Servers'][1]['verbose'] = 'Galera Node 1 (Primary)';
$cfg['Servers'][1]['compress'] = false;
$cfg['Servers'][1]['AllowNoPassword'] = false;

// Server 2: Galera Node 2
$cfg['Servers'][2]['auth_type'] = 'cookie';
$cfg['Servers'][2]['host'] = 'galera-node2';
$cfg['Servers'][2]['port'] = 3306;
$cfg['Servers'][2]['verbose'] = 'Galera Node 2';
$cfg['Servers'][2]['compress'] = false;
$cfg['Servers'][2]['AllowNoPassword'] = false;

// Server 3: Galera Node 3
$cfg['Servers'][3]['auth_type'] = 'cookie';
$cfg['Servers'][3]['host'] = 'galera-node3';
$cfg['Servers'][3]['port'] = 3306;
$cfg['Servers'][3]['verbose'] = 'Galera Node 3';
$cfg['Servers'][3]['compress'] = false;
$cfg['Servers'][3]['AllowNoPassword'] = false;

// Server 4: Galera Node 4
$cfg['Servers'][4]['auth_type'] = 'cookie';
$cfg['Servers'][4]['host'] = 'galera-node4';
$cfg['Servers'][4]['port'] = 3306;
$cfg['Servers'][4]['verbose'] = 'Galera Node 4';
$cfg['Servers'][4]['compress'] = false;
$cfg['Servers'][4]['AllowNoPassword'] = false;

// Server 5: HAProxy Load Balancer
$cfg['Servers'][5]['auth_type'] = 'cookie';
$cfg['Servers'][5]['host'] = 'haproxy';
$cfg['Servers'][5]['port'] = 3306;
$cfg['Servers'][5]['verbose'] = 'HAProxy Load Balancer';
$cfg['Servers'][5]['compress'] = false;
$cfg['Servers'][5]['AllowNoPassword'] = false;

// General phpMyAdmin settings
$cfg['LoginCookieValidity'] = 3600;
$cfg['DefaultLang'] = 'en';
$cfg['ServerDefault'] = 1; // Default to Node 1
$cfg['UploadDir'] = '';
$cfg['SaveDir'] = '';
$cfg['TempDir'] = '/tmp/';

// Security settings
$cfg['blowfish_secret'] = 'galera-cluster-phpmyadmin-secret-key-32chars';
?>
