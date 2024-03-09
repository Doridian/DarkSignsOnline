<?
	include_once 'function.php';
	
	echo '2003';
		
	if ($auth == '1001')
	{
		$port = $db->real_escape_string($_POST['port'], "[^0-9]");
		if ($port < 1 || $port > 65536)
		{
			die("Error: Port number must be between 1 and 65536.<end>");
		}
		
		
		$d = $db->real_escape_string($_POST['d']);
		$temp = getDomainInfo($d);
		
		if ($temp[0] > 0)
		{
			if ($user['id'] == $temp[1])
			{
				$code = $db->real_escape_string($_POST['filedata']);
				$db->query("INSERT INTO domainscripts VALUES ($temp[0], $port, '$code', '".$_SERVER['REMOTE_ADDR']."', ".time().") ON DUPLICATE KEY UPDATE code='$code', ip='".$_SERVER['REMOTE_ADDR']."', time=".time().";");
			
				if ($db->error)
				{
					die('fail<end>');
				}
				else
				{
					die('success<end>');
				}
			}
			else
			{
				die('Restricted access.<end>');
			}
		}
		else
		{
			die('Domain does not exist.<end>');
		}
	}
	else
	{
		die('Access denied.<end>');
	}
?>