<?
if (isset($returnwith)){}else{$returnwith="2000";}
$returnwith=trim($returnwith);
echo $returnwith;


include_once('mysql_config.php');
global $db;

$u=trim($u);
$p=trim($p);


if ($auth=="1001"){
	
	$amount2=number_format($amount);
	
	//-----------------------------------------------------------------------------
	//make the transaction
		if (transaction($u,$to,$description,$amount)==true){
		$usercash=number_format(grab_from_users("cash"));
		die("Payment of $$amount2 to $to is complete.newlineYour new balance is $$usercash.<end>");
	}else{
		$usercash=number_format(grab_from_users("cash"));
		die("Payment of $$amount2 to $to was DECLINED by the bank.newlineYour account balance of $$usercash may be insufficient.<end>");
	}
	//-----------------------------------------------------------------------------

	
}else{
	echo "Not Authorized, Access Denied.";
	die("<end>");
}
