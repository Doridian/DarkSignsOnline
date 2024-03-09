<?php
	include_once "function.php";

	$type = preg($_GET['type'], "[^a-z]");
	if ($auth == '1001')
	{
		echo 2001;
		if ($type == 'domain')
		{
			$loopQuery = mysql_query("SELECT i.id, d.name, d.ext FROM iptable AS i, domain AS d WHERE i.owner='$user[id]' AND i.regtype='DOMAIN' AND d.id=i.id");
			while ($loop = mysql_fetch_array($loopQuery))
			{
				$count = mysql_num_rows(mysql_query("SELECT id FROM subdomain WHERE hostid='$loop[id]'"));
								
				echo $loop['name'].'.'.$loop['ext'];
								
				if ($count > 0)
					echo '*';
				echo '$newline';
			}
		}
		else if ($type == 'subdomain')
		{
			$domain = preg($_GET['domain']);
			$domain = explode('.', $domain);
			if (sizeof($domain) == 2)
			{
				if (getOwner($domain[0], $domain[1]) == $user['id'])
				{
					$loopQuery = mysql_query("SELECT s.name FROM iptable AS i, domain AS d, subdomain AS s WHERE i.owner='$user[id]' AND i.id=d.id AND d.name='$domain[0]' AND d.ext='$domain[1]' AND d.id=s.hostid AND d.active=1 GROUP BY s.id");
					while ($loop = mysql_fetch_array($loopQuery))
					{
						echo $loop['name'].'.'.$domain[0].'.'.$domain[1].'$newline';
					}
				}
				else
				{
					echo 'Restricted access to domain.{red 15}';
				}
			}
			else
			{
				echo 'Invalid domain. Syntax : mySite.com';
			}
		}
		else if ($type == 'ip')
		{
			$loopQuery = mysql_query("SELECT ip FROM iptable WHERE owner='$user[id]' AND regtype='IP' AND active=1");
			while ($loop = mysql_fetch_array($loopQuery))
			{
				echo $loop['ip'].'$newline';
			}
		}
		else
		{
			echo 'Invalid type paramater.';
		}
	}
	else
	{
		echo 'Access Denied';
	}
	
	//echo "<end>";
?>