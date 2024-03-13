<?php
  function format_github_link($rev) {
    $rev = trim($rev);
    return '<a href="https://github.com/Doridian/DarkSignsOnline/tree/' . htmlentities($rev) . '/server">' . htmlentities($rev) . '</a>';
  }
?>
<br />
<br />
<center>
  <br />
  <span class="style3"><span class="style5">. . . </span><br />
    <strong>Dark Signs Online version
      <?php echo format_github_link(file_get_contents('api/gitrev.txt')); ?>
    </strong><br />
    Copyright &copy; 2008 Dark Signs Online<br />
    <a href="/index.php">Home</a>
    |
    <a href="/chatlog.php">Live Chat Log</a>
    |
    <a href="/termsofuse.php">Terms of use</a><br /><br /><br /><br /><br />
  </span>
</center>
</div>
</td>
</tr>
</tbody>
</table>
</body>

</html>