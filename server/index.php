<?php require('_top.php'); ?>
<span class="style5"><br />- News - <br /><br />

  <strong>March 22nd 2024</strong><br /><span class="style9">
    Completely redid the DSO scripting engine. It now uses (the safe subset of) VBScript.<br />
    There is also a parser to turn "CLI-like" language into VBScript for you.<br />
    More news soon!</span><br /><br />

  <strong>March 19th 2024</strong><br /><span class="style9">
    Most of the things should now be fixed up. Server scripts and domain filesystem commands fully work.<br />
    The big areas that still need fixing are (all server-only fixes) <i>transactions</i>, <i>DSMail</i> and <i>the library</i>
    (likely in the order I will fix them)</span><br /><br />

  <strong>March 17th 2024</strong><br /><span class="style9">
    Decoded to work on the Wiki today. The Wiki link up top now links to this server, no longer to archive.org.<br />
    I have restored all archived pages to their original state and fixed some typos.</span><br /><br />

  <strong>March 17th 2024</strong><br /><span class="style9">
    Managed to recover at least the startup script files from the leftover "zlog.dat" file.<br />
    Seems to have been a console log, sadly all it ever logged was the startup script.<br />
    The two big things that still need to be restored for basic functionality are as follows:
    <b>Domain filesystem (SERVER WRITE, etc)</b> and some <b>built-in commands</b> (the ones written in
    DScript)</span><br /><br />

  <strong>March 16th 2024</strong><br /><span class="style9">
    Worked on and off on the source of both server and client over the past few days.<br />
    Things are starting to come together. The client is possibly fully ready.<br />
    The server side functions related to domains are mostly in working order once again.<br />
    Sadly, the domain filesystem part needs a lot of attention, but it should be doable!</span><br /><br />

  <strong>March 9th 2024</strong><br /><span class="style9">
    Currently working on restoring the old source code.<br />
    The copy I got (linked below) is of the latest in-dev code
    base, which had several unifnished changes, so I am
    finishing those up.<br />
    The basic game is mostly able to run again.<br />
    Currently fixing the server-side up to be secure for
    today's standards...
    <br />If anyone can find an old copy of DSO, feel free to
    send it over for archival as well.<br />
    You can also watch my work (almost) live on
    <a href="https://github.com/Doridian/DarkSignsOnline">github.com/Doridian/DarkSignsOnline</a></span><br /><br />

  <strong>March 8th 2024</strong><br /><span class="style9">
    Hello again, I did not expect to have to post an update so
    soon, however there is some good news!<br />
    Thanks to my old friend Saberuneko, who I was surprised to
    learn happened to hold onto a copy of the client and
    server source code,<br />
    I now have the mentioned code in my hands. I will try to
    get it compiled and running again, no new features or
    anything, just like it used to be.<br />
    For anyone curious, you can download the code here:
    <a href="/dso.zip">Client</a> |
    <a href="/dsoserv.zip">Server</a></span><br /><br />

  <strong>March 7th 2024</strong><br /><span class="style9">
    Hey everyone,
    <a target="_blank" href="https://web.archive.org/web/20110724080717/http://www.darksignsonline.com/forum/viewtopic.php?f=2&t=956">Doridian
      (archive.org)</a>
    here. I used to work on DSO way back when and just
    realized the domain was free so I grabbed it.<br />
    No idea what I will do with it, but better than some
    parking company having it.<br />
    If anyone finds versions of the client or other DSO
    related things, please let me know. I would love to have
    them for the archive.<br />
    E-Mail:
    <a href="mailto:doridian@darksignsonline.com">doridian@darksignsonline.com</a><br />
    Fedi:
    <a href="https://furry.engineer/@Doridian">@furry.engineer@Doridian</a></span><br /><br />

  <strong>March 7th 2008</strong><br /><span class="style9">Just released DSO 0.8.1, contains minor bug fixes, plus
    afew new features. See
    <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/forum/viewtopic.php?f=2&amp;t=269">here
      (archive.org)</a>
    for more info.</span><br /><br />

  <strong>March 5th 2008</strong><br /><span class="style9">DSO 0.80 released :). View changes
    <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/forum/viewtopic.php?f=2&amp;t=263">here
      (archive.org)</a>.
  </span><br /><br />

  <strong>March 4th 2008</strong><br /><span class="style9">Sorry for the delay, but the next DSO release will be
    within the next 12 hours.</span><br /><br />

  <strong>February 3rd 2008 </strong><br /><span class="style9">A new update will be available in the near future.
  </span><strong><br /><br />January 14th 2008 </strong><br /><span class="style9">A <span class="style17"><em>must
        have</em></span> update
    is available.<br /><a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/download.php">Download v0.77
      here. (archive.org)</a><br /></span></span>
<table width="600" border="0" cellpadding="15" cellspacing="0" bgcolor="#1B1B1B">
  <tbody>
    <tr>
      <td>
        <font face="verdana" size="2"><strong>Notes: </strong>You can now use $p1, $p2,
          $p3, etc, for your script parameter variable names
          from within your script. The problem with using $1,
          $2, etc, is that it may interfere if you are trying
          to display how much an item might cost, in dollars.
          Although both of these will work for now, try to use
          $p1, $p2, etc. <br />
          <br />
        </font>
        <font face="verdana"><span class="style13">New features</span></font>
        <font face="verdana" size="2"><br />
          <br />
          <strong>DRAW Command<br /> </strong><a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=139">http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=139
            (archive.org)</a><br />
          <br />
          <strong>Bunches of bugs fixed.</strong><br />
          <br />
          <strong>Encoding - secure scripts on your domains</strong><br />
          <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=137">http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=137
            (archive.org)</a><br />
          <br />
          <strong>REMOTEVIEW command added</strong>
        </font>
      </td>
    </tr>
  </tbody>
</table>
<span class="style5"><strong><strong><strong><br />
        <br />January 13th 2008 </strong><span class="style16"><span class="style17"><br /></span> The DRAW command
        has been added!<br /></span><strong><a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/dsodraw3.png" target="_top"><img src="/dsodraw3small.png" width="284" height="213" border="1" /></a></strong>
      <strong><strong><a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/dsodraw4.png" target="_top">
            <img src="/dsodraw4small.png" width="287" height="215" border="1" /></a></strong></strong><br /><br />January
      12th 2008 </strong><br /> </strong><span class="style9">New update available -
    <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/download.php">version 0.74
      (archive.org)</a>~!
  </span><br />
</span>
<table width="600" border="0" cellpadding="15" cellspacing="0" bgcolor="#1B1B1B">
  <tbody>
    <tr>
      <td>
        <font face="verdana" size="2"><strong>Changes: </strong>You can now use
          <em><strong>$serverdomain</strong></em> and
          <em><strong>$serverip</strong></em> in the scripts
          that you upload to your domain names. When someone
          connects, these variables will be replaced
          automatically with the domain name and ip address
          from which the script is running. <br />
          <br />
        </font>
        <font face="verdana"><span class="style13">New features</span></font>
        <font face="verdana" size="2"><br />
          <br />
          <strong>Text Space Area</strong> - Check it out in
          the file database, it might be just what you need
          one day. <br />
          <br />
          <strong>SAYALL </strong> <strong> - </strong>Command
          to SAY multiple lines at once. <br />
          <br />
          <strong>Functions: </strong>fileexists(filename) and
          direxists(directoryname)<br />
          <br />
          <strong>Public Files for your servers! </strong><br />
          <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=119">http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=119
            (archive.org)</a>
        </font>
      </td>
    </tr>
  </tbody>
</table>
<span class="style5"><br />
  <br />
  <strong><strong>January 12th 2008 </strong><br /> </strong><span class="style9">A
    <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/chatlog-light.php">light
      version (archive.org)</a>
    of the live chat log is available. </span><br />
  <br />
  <strong><strong>January 11th 2008 </strong><br /> </strong><span class="style9"><a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/download.php">Download
      (archive.org)</a>
    the new update, 0.73. <br /> </span></span>
<table width="600" border="0" cellpadding="15" cellspacing="0" bgcolor="#1B1B1B">
  <tbody>
    <tr>
      <td>
        <font face="verdana" size="2"><strong>Changes: </strong>You can now use
          <em><strong>$tab</strong></em> for a TAB in your
          code, or <em><strong>$newline</strong></em> for a
          new line. Multiple bugs continue to be repaired. If
          yours hasn't been fixed yet, please post it in the
          forum. Remember that SAY will not show new lines.
          (SAY only shows the first line if there are multiple
          lines). <br />
          <br />
        </font>
        <font face="verdana"><span class="style13">New features</span></font>
        <font face="verdana" size="2"><br />
          <br />
          <strong>New Transfer Functions</strong>
          <strong> - </strong>Get the status of transfers, and
          more. <br />
          <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=98">http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=98
            (archive.org)</a><br />
          <br />
          <strong>New Remote File System Commands and
            Functions</strong><br />
          <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=104">http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=104
            (archive.org)</a><br />
          <br />
          <strong>SUBOWNERS Command</strong><br />
          <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=100">http://www.darksignsonline.com/forum/viewtopic.php?f=9&amp;t=100
            (archive.org)</a>
        </font>
      </td>
    </tr>
  </tbody>
</table>
<span class="style5"><strong><br /> </strong><br />
  <strong><strong>January 9th 2008 </strong><br /> </strong><span class="style9">Yet another update is
    <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/download.php">available
      (archive.org)</a>,
    version 0.72, mostly scripting fixes.</span><strong><br /> </strong><strong><br />January 8th 2008
  </strong><br /><span class="style9">Dark Signs Online
    <em><strong>update is available</strong></em> -
    <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/download.php">download the update
      now! (archive.org)</a><br /></span></span>
<br />
<table width="600" border="0" cellpadding="15" cellspacing="0" bgcolor="#1B1B1B">
  <tbody>
    <tr>
      <td>
        <font face="verdana" size="2"><strong>Additions and changes:</strong> fileserver
          function, UNREGISTER command, .. bugs fixed, misc
          bugs fixed, increased security functionality, added
          $now variable, download(url) function fixed, LINEUP
          command, SAYLINE command, and fixed script database
          problem.<br />
          <br />
          <span class="style12"><strong>Note:</strong> If you have existing
            scripts in the script database, it is a good idea
            to reupload them. (Previously, + characters were
            being lost).
          </span>
        </font>
      </td>
    </tr>
  </tbody>
</table>
<span class="style5"><br />
  <br />
  <strong>January 8th 2008 </strong><br />
  <span class="style9">An update to Dark Signs Online will be available soon.
    <br />The Dark Signs Online Wiki is
    <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/wiki/">also online,
      (archive.org)</a></span>
  and requires editors. <br /><br /><br /><strong>January 7th 2008 </strong><br /><span class="style9">The first release
    of Dark Signs Online is
    <a href="https://web.archive.org/web/20101231205551/http://www.darksignsonline.com/download.php">available for
      download. (archive.org)</a></span><br /><br /><br /><strong>January 4th 2008 </strong><br /><span class="style9">The first beta
    version is due before the 15th of
    January.</span></span><br /><br />
<br />
<?php require('_bottom.php');
