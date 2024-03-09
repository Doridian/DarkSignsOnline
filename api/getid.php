<?php
	include_once 'function.php';

	echo $db->real_escape_string($_GET['d'], "[^a-zA-Z0-9./\-]");
	//$a = getDomainInfo($_GET['d']);
	
	//echo "<br /><br />";
	//print_r($a);
?>