<?php
	include_once 'function.php';
	global $auth;

	echo '2003';
		
	if ($auth == '1001')
	{
		$port = (int)$_POST['port'];
		if ($port < 1 || $port > 65536)
		{
			die("Error: Port number must be between 1 and 65536.");
		}
		
		
		$d = $_POST['d'];
		$temp = getDomainInfo($d);
		
		if ($temp[0] > 0)
		{
			if ($user['id'] == $temp[1])
			{
				$code = $_POST['filedata'];
				$db->query("INSERT INTO domainscripts VALUES ($temp[0], $port, '$code', '".$_SERVER['REMOTE_ADDR']."', ".time().") ON DUPLICATE KEY UPDATE code='$code', ip='".$_SERVER['REMOTE_ADDR']."', time=".time().";");
			
				if ($db->error)
				{
					die('fail');
				}
				else
				{
					die('success');
				}
			}
			else
			{
				print_r($user);
				print_r($temp);
				die('Restricted access.');
			}
		}
		else
		{
			die('Domain does not exist.');
		}
	}
	else
	{
		die('Access denied.');
	}
