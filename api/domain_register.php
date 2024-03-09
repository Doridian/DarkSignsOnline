<?php

	include_once 'function.php';
	
	// Return code for domain register.
	echo '2000';
	
	if ($auth == '1001')
	{
		$d = strtolower($db->real_escape_string($_POST['d']));

		$temp = getDomainInfo($d);
		
		if ($temp[0] == -1)
		{
			// List of prices.
			$price['com'] = 120;
			$price['net'] = 80;
			$price['org'] = 80;
			$price['edu'] = 299;
			$price['mil'] = 1499;
			$price['gov'] = 1499;
			$price['dsn'] = 12999;
			
			$domain = explode('.', $d);			
			
			if (sizeof($domain) == 2)
			{
				// Normal domain register.
				$ext = $domain[1];
				if ($ext == 'com' || $ext == 'net' || $ext == 'org' || $ext == 'edu' || $ext == 'mil' || $ext == 'gov' || $ext == 'dsn')
				{
					if ($price[$ext] > $user['cash'])
					{
						die('Insufficient balance. Try again when you have more money.<end>');
					}
					else
					{
						//echo $user['name'];
						if (transaction($user['username'], 'bank', 'Domain Registration: '.$d, $price[$ext]))
						{
							// Generate IP
							$randomip;
							$query;
							do
							{
								$randomip = rand(1,255).".".rand(1,255).".".rand(1,255).".".rand(1,255);
								$query = $db->query("SELECT * FROM iptable WHERE ip='$randomip'");
							} while ($db->num_rows($query) != 0);
						
							if (sizeof($domain) == 2)
							{
								$db->query("INSERT INTO iptable (owner, ip) VALUES ($user[id], '$randomip')");
								$id = $db->insert_id;
								$db->query("INSERT INTO domain (id, name, ext, time, ip) VALUES ($id, '".$domain[0]."', '".$domain[1]."', '".time()."', '".$_SERVER['REMOTE_ADDR']."')") or die($db->error); 
							}

							die('Registration complete for '.$d.', you have been charged $'.$price[$ext].'<end>');
						}
						else
						{
							die('Registration of '.$d.' has been DECLINED by the Dark Signs Bank.newlineCheck your bank account for further details.<end>');
						}
		
					}
				}
				else
				{
					die('Invalid domain extention.<end>');
				}
			
			}
			else if (sizeof($domain) == 3)
			{
				// Subdomain register.
				$ext = $domain[2];
				$price = 20;
				if ($ext == 'com' || $ext == 'net' || $ext == 'org' || $ext == 'edu' || $ext == 'mil' || $ext == 'gov' || $ext == 'dsn' || ($ext == 'usr' && $user['username'] == $domain[1]))
				{
					$temp2 = getDomainInfo($domain[1].'.'.$domain[2]);
					if ($temp2[1] != $user['id'])
					{
						die($temp[1].'  '.$user['id'].'  You must be the owner of the full domain to register a sub domain.');
					}
					else if ($price > $user['cash'])
					{
						die('Insufficient balance. Try again when you have more money.<end>');
					}
					else
					{	
						if (transaction($user['username'], 'bank', 'Domain Registration: '.$d, $price))
						{
							// Generate IP
							$randomip;
							$query;
							do
							{
								$randomip = rand(1,255).".".rand(1,255).".".rand(1,255).".".rand(1,255);
								$query = $db->query("SELECT * FROM iptable WHERE ip='$randomip'");
							} while ($db->num_rows($query) != 0);
						
							$db->query("INSERT INTO iptable (owner, ip, regtype) VALUES ($user[id], '$randomip', 'SUBDOMAIN')");

							$id = $db->insert_id;
							
							$db->query("INSERT INTO subdomain (id, hostid, name, time, ip) VALUES ($id, $temp2[0], '".$domain[0]."', '".time()."', '".$_SERVER['REMOTE_ADDR']."')") or die($db->error); 

							die('Registration complete for '.$d.', you have been charged $'.$price.'<end>');
						}
						else
						{
							die('Registration of '.$d.' has been DECLINED by the Dark Signs Bank.newlineCheck your bank account for further details.<end>');
						}
		
					}
				}
				else
				{
					die('Invalid domain extention.<end>');
				}
			}
			else if (sizeof($domain) == 4)
			{
				// IP register.
				$domain[0] = intval($domain[0]);
				$domain[1] = intval($domain[1]);
				$domain[2] = intval($domain[2]);
				$domain[3] = intval($domain[3]);
				
				if ($domain[0] >= 0 && $domain[0] < 256 && $domain[1] >= 0 && $domain[1] < 256 && $domain[2] >= 0 && $domain[2] < 256 && $domain[3] >= 0 && $domain[3] < 256)
				{
					// IP is valid.
					$ip_exists = $db->num_rows($db->query("SELECT id FROM iptable WHERE ip='$domain[0].$domain[1].$domain[2].$domain[3]'"));
					
					if ($ip_exists == 0)
					{
						// All good, register IP.
						$price = 40; // static price for IP registrations.
						if ($price > $user['cash'])
						{
							die($user['cash'].'  Insufficient balance. Try again when you have more money.<end>');
						}
						else
						{
							if (transaction($user['username'], 'bank', 'Domain Registration: '.$domain[0].'.'.$domain[1].'.'.$domain[2].'.'.$domain[3], $price))
							{
								$db->query("INSERT INTO iptable (owner, ip, regtype) VALUES ($user[id], '$domain[0].$domain[1].$domain[2].$domain[3]', 'IP')");
								if ($db->error)
								{
									die('A server error occured. Please report this to BigBob85 via DSO forums.<end>');
								}
								else
								{
									die('Registration complete for '.$domain[0].'.'.$domain[1].'.'.$domain[2].'.'.$domain[3].', you have been charged $'.$price.'.<end>');
								}
							}
							else
							{
								die('Registration of '.$domain[0].'.'.$domain[1].'.'.$domain[2].'.'.$domain[3].' has been DECLINED by the Dark Signs Bank.newlineCheck your bank account for further details.<end>');
							}
						}
					}
					else
					{
						// Fail, ip exists.
						die('The IP address you tried to register already exists: '.$d.'<end>');
					}
				} 
				else
				{
					die('The IP address you tried to register was invalid: '.$d.'<end>');
				}
			}
			else
			{
				die('The domain name is invalid: '.$d.'<end>');
			}		
		}
		else
		{
			die('Domain '.$d.' is already registed.<end>');
		}			
	}
	else
	{
		echo 'Not Authorized, Access Denied.';
	}

	echo '<end>';	
?>