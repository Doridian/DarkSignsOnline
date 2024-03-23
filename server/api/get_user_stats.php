<?php

include_once "function.php";

print_returnwith();

echo 'STATS: You have $'.number_format(getCash($user['id'])).'.';
