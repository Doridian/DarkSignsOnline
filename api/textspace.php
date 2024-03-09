<?php
	include_once 'function.php';
	
	if ($auth == '1001')
	{
		$action = preg($_REQUEST['action']);
		if ($action == 'download')
		{
			$data = preg($_REQUEST['data']);
			$result = mysql_query("SELECT `text` FROM textspace WHERE chan='$data' ORDER BY rev DESC LIMIT 1") or die(mysql_error());;
			if (mysql_num_rows($result) == 1)
			{
				die('4501'.mysql_result($result, 0));
			}
			else
			{
				die('4501  <end>');				
			}
			while($row = mysql_fetch_array( $result )) {$textdata=$row['data'];}
			
		}
		else if ($action == 'upload')
		{
			$chan = preg($_REQUEST['chan'], "[^0-9]");
			if ($chan == "")
			{
				die('4500Invalid channel.<end>');						
			}
			else if ($chan == '001')
			{
				die('4500Modification Denied.<end>');
			}
			$chan = intval($chan);
		
			$data = $_REQUEST['data']; // Get some error checking.
			$time = time();
			//echo 'XXXZ         '.$chan;
			$result = mysql_query("SELECT rev FROM textspace WHERE chan=$chan ORDER BY rev DESC LIMIT 1");
			if (mysql_num_rows($result) == 0)
			{
				//$result = mysql_query("INSERT INTO `textspace` (`rev`, `chan`, `user`, `lastupdate`, `text`, `active`) VALUES (1, $chan, 1, 1234, 'test', 1);") or die('X '.mysql_error().' (B)');
				$result = mysql_query("INSERT INTO textspace (`rev`, `chan`, `user`, `lastupdate`, `text`, `active`) VALUES (1, $chan, $user[id], $time, '$data', 1)") or die('X '.mysql_error().' (B)');
			}
			else
			{
				$rev = mysql_result($result, 0)+1;
				$result = mysql_query("INSERT INTO textspace (`rev`, `chan`, `user`, `lastupdate`, `text`) VALUES ($rev, $chan, $user[id], $time, '$data')") or die('X '.mysql_error().' (C)');
				
			}
			
			die("4500Updated: $chan!<end>");
			
		}	
	}
	echo '<end>';	
?>