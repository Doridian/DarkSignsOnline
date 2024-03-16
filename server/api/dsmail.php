<?php
	include_once "function.php";

	$returnwith = (string)(int)$_REQUEST['returnwith'];
	if ($returnwith === '0')
	{
		$returnwith = '7000';
	}
	
	echo $returnwith;
	
	if ($auth == '1001')
	{
		$action = $_REQUEST['action'];
		if ($action == 'inbox')
		{
			
			$last = (string)(int)$_REQUEST['last'];
			$result = $db->query("SELECT mail_id,user_id, from_id, subject, message, time FROM dsminbox WHERE user_id='{$user['id']}' AND mail_id > $last ORDER BY mail_id ASC");
		
			
			if ($db->error) {
				die($db->error . '');
			}
			
			while ($mail = $db->fetch_array($result))
			{
				echo 'X_'.$mail['mail_id'].chr(7).idToUser($mail['from_id']).chr(7).$mail['subject'].chr(7).$mail['message'].chr(7).$mail['time']."\n";
			}
		}
		else if ($action == 'send')
		{
			$from = $user['id'];
			$to = $_REQUEST['to'];
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
				$sub = preg_replace("[^a-zA-Z0-9., \-]", "", $_REQUEST['subject']);
				$msg = preg_replace("[^a-zA-Z0-9., ".chr(6)."\-]", "", $_REQUEST['message']);
				
				foreach ($nameID as $id)
				{
					$result = $db->query("SELECT MAX(mail_id) FROM dsminbox WHERE user_id=$id");
					$mail_id = 1;
					if ($db->num_rows($result) == 1)
					{
						$mail_id = $db->result($result, 0)+1;
					}
					$db->query("INSERT INTO dsminbox (user_id, from_id, mail_id, status, subject, message, time, ip) VALUES ($id, {$user['id']}, $mail_id, 0, '$sub', '$msg', ".time().", '".$_SERVER['REMOTE_ADDR']."')");
					
					if ($db->error)
					{
						$safeSend = false;
						echo $db->error;
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
