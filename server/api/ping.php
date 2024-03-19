<?php
	include_once 'function.php';
	
	if ($auth == '1001')
	{
		$domain = $_POST['domain'];
		$port = (int)$_POST['port'];

		$dInfo = getDomainInfo($domain);
		if ($dInfo[0] > 0)
		{
			if($port == 0)
			{
				echo 1;
			}
			else
			{
				$query = $db->query("SELECT domain_id FROM domain_scripts WHERE domain_id=$dInfo[0] AND port=$port");
				
				//list($isport) = $db->fetch_row($db->query('SELECT code FROM domain_scripts WHERE domain_id = "'.$dInfo[0].'" AND port = "'.$port.'";'));
				//if (!empty($isport))
				
				if ($db->num_rows($query) == 1)
				{
					echo 1;
				}
				else
				{
					echo 0;
				}
			}
		}
		else
		{
			echo 0;
		}		
	}
