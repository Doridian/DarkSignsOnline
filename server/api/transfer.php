<?php

include_once('function.php');
global $db;


print_returnwith();

$u=trim($u);
$p=trim($p);

$amount2=number_format($amount);

if (transaction($u,$to,$description,$amount)==true){
	$usercash=number_format(grab_from_users("cash"));
	die("Payment of $$amount2 to $to is complete.newlineYour new balance is $$usercash.");
}else{
	$usercash=number_format(grab_from_users("cash"));
	die("Payment of $$amount2 to $to was DECLINED by the bank.newlineYour account balance of $$usercash may be insufficient.");
}
