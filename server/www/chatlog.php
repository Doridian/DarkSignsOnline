<?php

$htmltitle = 'Live Chat Log';
require('_top.php');
require_once('_function_base.php');

// The in-game chat, read-only and without an account. The client writes
// these rows through `api/chat.php`; this page is the window onto them the
// site has always promised.

/** As many as fit on a page someone is skimming, newest first. */
define('CHATLOG_LINES', 100);

$stmt = $db->prepare(
    'SELECT c.action, c.message, c.time, u.username
     FROM chat c JOIN users u ON u.id = c.user
     ORDER BY c.id DESC LIMIT ?'
);
$limit = CHATLOG_LINES;
$stmt->bind_param('i', $limit);
$stmt->execute();
$lines = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);

?>
<span class="style5"><br />

    <p><br />
        <font face="Georgia, Times New Roman, Times, serif" size="+3">Live Chat Log</font><br />
        <br />
        <font face="Georgia, Times New Roman, Times, serif" size="3">The most recent messages are shown first</font>
        <br />
    </p>
    <table width="700" border="0">
        <tr>
            <td>
                <div align="left">
                    <font face="verdana" size="2">
<?php if (empty($lines)) { ?>
                        <font color="#00CC00"><b>* Dark Signs Online --- Nobody has said anything yet ---</b></font><br>
<?php } else {
    foreach ($lines as $line) {
        $who = htmlspecialchars($line['username'], ENT_QUOTES, 'UTF-8');
        $what = htmlspecialchars($line['message'], ENT_QUOTES, 'UTF-8');
        $when = date('d.m.Y H:i:s', $line['time']);
        // An emote is the `/me` the original sent as a CTCP ACTION, and it
        // reads as one here too: "* nick does something".
        if ($line['action']) { ?>
                        <font color="#6699FF">[<?= $when ?>] * <?= $who ?> <?= $what ?></font><br>
<?php   } else { ?>
                        <font color="#00CC00">[<?= $when ?>] &lt;<?= $who ?>&gt; <?= $what ?></font><br>
<?php   }
    }
} ?>
                    </font>
                </div>
            </td>
        </tr>
    </table>
    <br />
    <br />
</span>
<?php require('_bottom.php');
