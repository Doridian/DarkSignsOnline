<?
	include_once 'function.php';
	global $auth;

	echo '4100';

	if ($auth == '1001')
	{
		$port = (int)$_REQUEST['port'];

		if ($port < 1 || $port > 65536)
		{
			die('not found<end>');
		}
		$d = $_REQUEST['d'];
		$d = strtolower($d); 
		$temp = getDomainInfo($d);

		if ($temp[0] > 0)
		{
			$exists = $db->query("SELECT code FROM domainscripts WHERE domain_id='$temp[0]' AND port=$port") or die($db->error);
			if ($exists->num_rows == 1)
			{
				$code = $exists->fetch_row();
				echo $d.'_'.$port.'::'.$code[0];
			}
			else
			{
				echo 'not found';
			}
		}
		else
		{
			echo 'not found';
		}
	}
	else
	{
		echo 'Access Denied';
	}
	
	echo '<end>';

?>
