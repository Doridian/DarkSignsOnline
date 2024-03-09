<?php
	include_once "function.php";

	$returnwith = preg($_REQUEST['returnwith'], "[^0-9]");
	if (empty($returnwith))
	{
		$returnwith = '7000';
	}
	
	echo $returnwith;
	
	if ($auth == '1001')
	{
		$action = preg($_REQUEST['action']);
		if ($action == 'inbox')
		{
			
			$last = preg($_REQUEST['last'], "[^0-9]");
			
			if (empty($last))
			{
				$last = '0';
			}
			$result = mysql_query("SELECT mail_id,user_id, from_id, subject, message, time FROM dsminbox WHERE user_id='{$user['id']}' AND mail_id > $last ORDER BY mail_id ASC");
		
			
			if (mysql_error())
				echo mysql_error();
			
			while ($mail = mysql_fetch_array($result))
			{
				echo 'X_'.$mail['mail_id'].chr(7).idToUser($mail['from_id']).chr(7).$mail['subject'].chr(7).$mail['message'].chr(7).$mail['time']."\n";
			}
		}
		else if ($action == 'send')
		{
			$from = $user['id'];
			$to = preg($_REQUEST['to']);
			$toArr = explode(',', $to);
			
			if (sizeof($toArr) > 10)
			{
				die ('Cant send mail to more than 10 people.');
			}
			
			$safeSend = true;
			$nameID = Array();
			foreach ($toArr as $name)
			{
				$tmpID = userToId($name);
				if ($tmpID == -1)
				{
					$safeSend = false;
					break;
				}
				else
				{
					array_push($nameID, $tmpID);
				}				
			}
			
			if ($safeSend)
			{
				$sub = preg($_REQUEST['subject'], "[^a-zA-Z0-9., \-]");
				$msg = preg($_REQUEST['message'], "[^a-zA-Z0-9., ".chr(6)."\-]");
				
				foreach ($nameID as $id)
				{
					$result = mysql_query("SELECT MAX(mail_id) FROM dsminbox WHERE user_id=$id");
					$mail_id = 1;
					if (mysql_num_rows($result) == 1)
					{
						$mail_id = mysql_result($result, 0)+1;
					}
					mysql_query("INSERT INTO dsminbox (user_id, from_id, mail_id, status, subject, message, time, ip) VALUES ($id, {$user['id']}, $mail_id, 0, '$sub', '$msg', ".time().", '".$_SERVER['REMOTE_ADDR']."')");
					
					if (mysql_error())
					{
						$safeSend = false;
						echo mysql_error();
						break;
					}
				}
				
				if ($safeSend)
					echo 'success';
				
			}
			else
			{
				echo 'Unknown name: '.$name;
			}

		}
		else
		{
			echo 'no request found.';
		}
	}
	else
	{
		echo 'Access Denied 65233';
	}

	echo '<end>';
?>