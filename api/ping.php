<?php
	include_once 'function.php';
	
	if ($auth == '1001')
	{
		$domain = preg($_POST['domain']);
		$port = preg($_POST['port'], "[^0-9]");
		
		$temp = getDomainInfo($domain);
		if ($temp[0] > 0)
		{
			if($port == 0)
			{
				echo 1;
			}
			else
			{
				$query = mysql_query("SELECT domain_id FROM domainscripts WHERE domain_id=$temp[0] AND port=$port");
				
				//list($isport) = mysql_fetch_row(mysql_query('SELECT code FROM domainscripts WHERE domain_id = "'.$temp[0].'" AND port = "'.$port.'";'));
				//if (!empty($isport))
				
				if (mysql_num_rows($query) == 1)
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
	echo '<end>';	
?>