<?php
	include_once 'function.php';
	
	if ($auth == '1001')
	{
		$action = $db->real_escape_string($_REQUEST['action']);
		if ($action == 'download')
		{
			$data = $db->real_escape_string($_REQUEST['data']);
			$result = $db->query("SELECT `text` FROM textspace WHERE chan='$data' ORDER BY rev DESC LIMIT 1") or die($db->error);;
			if ($db->num_rows($result) == 1)
			{
				die('4501'.$db->result($result, 0));
			}
			else
			{
				die('4501  <end>');				
			}
			while($row = $db->fetch_array( $result )) {$textdata=$row['data'];}
			
		}
		else if ($action == 'upload')
		{
			$chan = $db->real_escape_string($_REQUEST['chan'], "[^0-9]");
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
			$result = $db->query("SELECT rev FROM textspace WHERE chan=$chan ORDER BY rev DESC LIMIT 1");
			if ($db->num_rows($result) == 0)
			{
				//$result = $db->query("INSERT INTO `textspace` (`rev`, `chan`, `user`, `lastupdate`, `text`, `active`) VALUES (1, $chan, 1, 1234, 'test', 1);") or die('X '.$db->error.' (B)');
				$result = $db->query("INSERT INTO textspace (`rev`, `chan`, `user`, `lastupdate`, `text`, `active`) VALUES (1, $chan, $user[id], $time, '$data', 1)") or die('X '.$db->error.' (B)');
			}
			else
			{
				$rev = $db->result($result, 0)+1;
				$result = $db->query("INSERT INTO textspace (`rev`, `chan`, `user`, `lastupdate`, `text`) VALUES ($rev, $chan, $user[id], $time, '$data')") or die('X '.$db->error.' (C)');
				
			}
			
			die("4500Updated: $chan!<end>");
			
		}	
	}
	echo '<end>';	
?>