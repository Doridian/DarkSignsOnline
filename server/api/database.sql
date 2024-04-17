-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: localhost
-- Generation Time: Apr 13, 2024 at 08:05 PM
-- Server version: 10.6.17-MariaDB
-- PHP Version: 7.4.33

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `darksignsonline`
--

-- --------------------------------------------------------

--
-- Table structure for table `domain`
--

CREATE TABLE `domain` (
  `id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `ext` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `domain_files`
--

CREATE TABLE `domain_files` (
  `id` int(11) NOT NULL,
  `domain` int(11) NOT NULL,
  `filename` varchar(4096) NOT NULL,
  `contents` longtext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `domain_scripts`
--

CREATE TABLE `domain_scripts` (
  `domain_id` int(11) NOT NULL,
  `port` int(11) NOT NULL,
  `code` longtext NOT NULL,
  `ip` varchar(255) NOT NULL,
  `time` int(11) NOT NULL,
  `ver` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `dsmail`
--

CREATE TABLE `dsmail` (
  `id` int(11) NOT NULL,
  `to_user` int(11) NOT NULL,
  `from_user` int(11) NOT NULL,
  `subject` varchar(4096) NOT NULL,
  `message` longtext NOT NULL,
  `time` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `file_database`
--

CREATE TABLE `file_database` (
  `id` int(11) NOT NULL,
  `owner` int(11) NOT NULL,
  `filename` varchar(255) NOT NULL,
  `version` varchar(255) NOT NULL,
  `title` longtext NOT NULL,
  `description` longtext NOT NULL,
  `createtime` int(11) NOT NULL,
  `ip` varchar(255) NOT NULL,
  `deleted` tinyint(1) NOT NULL,
  `category` varchar(255) NOT NULL,
  `ver` int(11) NOT NULL,
  `filedata` longtext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `iptable`
--

CREATE TABLE `iptable` (
  `id` int(11) NOT NULL,
  `owner` int(11) NOT NULL,
  `ip` varchar(255) NOT NULL,
  `regtype` enum('DOMAIN','SUBDOMAIN','IP') NOT NULL DEFAULT 'DOMAIN',
  `keycode` varchar(255) NOT NULL,
  `time` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `subdomain`
--

CREATE TABLE `subdomain` (
  `id` int(11) NOT NULL,
  `hostid` int(11) NOT NULL,
  `name` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `textspace`
--

CREATE TABLE `textspace` (
  `id` int(11) NOT NULL,
  `chan` int(11) NOT NULL,
  `owner` int(11) NOT NULL,
  `lastupdate` int(11) NOT NULL,
  `text` longtext NOT NULL,
  `deleted` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `transactions`
--

CREATE TABLE `transactions` (
  `id` int(11) NOT NULL,
  `fromid` int(11) NOT NULL,
  `toid` int(11) NOT NULL,
  `amount` int(11) NOT NULL,
  `description` varchar(4096) NOT NULL,
  `vercode` varchar(255) NOT NULL,
  `time` int(11) NOT NULL,
  `status` varchar(255) NOT NULL,
  `ip` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `username` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `active` tinyint(1) NOT NULL,
  `email` varchar(255) NOT NULL,
  `createtime` int(11) NOT NULL,
  `ip` varchar(255) NOT NULL,
  `lastseen` int(11) NOT NULL,
  `dobday` int(11) NOT NULL,
  `dobmonth` int(11) NOT NULL,
  `dobyear` int(11) NOT NULL,
  `emailverifycode` varchar(255) NOT NULL,
  `cash` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `domain`
--
ALTER TABLE `domain`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name_ext` (`name`,`ext`);

--
-- Indexes for table `domain_files`
--
ALTER TABLE `domain_files`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `domain_filename` (`domain`,`filename`) USING HASH;

--
-- Indexes for table `domain_scripts`
--
ALTER TABLE `domain_scripts`
  ADD UNIQUE KEY `id_port_ver` (`domain_id`,`port`,`ver`) USING BTREE,
  ADD KEY `id` (`domain_id`);

--
-- Indexes for table `dsmail`
--
ALTER TABLE `dsmail`
  ADD PRIMARY KEY (`id`),
  ADD KEY `to_user` (`to_user`),
  ADD KEY `from_user` (`from_user`);

--
-- Indexes for table `file_database`
--
ALTER TABLE `file_database`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `filename_version_ver` (`filename`,`version`,`ver`) USING BTREE,
  ADD KEY `owner` (`owner`),
  ADD KEY `deleted` (`deleted`),
  ADD KEY `category` (`category`),
  ADD KEY `ver` (`ver`);

--
-- Indexes for table `iptable`
--
ALTER TABLE `iptable`
  ADD PRIMARY KEY (`id`),
  ADD KEY `ip` (`ip`),
  ADD KEY `owner` (`owner`),
  ADD KEY `regtype` (`regtype`);

--
-- Indexes for table `subdomain`
--
ALTER TABLE `subdomain`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `hostid_name` (`hostid`,`name`),
  ADD KEY `hostid` (`hostid`);

--
-- Indexes for table `textspace`
--
ALTER TABLE `textspace`
  ADD PRIMARY KEY (`id`),
  ADD KEY `owner` (`owner`),
  ADD KEY `chan` (`chan`),
  ADD KEY `deleted` (`deleted`);

--
-- Indexes for table `transactions`
--
ALTER TABLE `transactions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fromid` (`fromid`),
  ADD KEY `toid` (`toid`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `username` (`username`),
  ADD UNIQUE KEY `email` (`email`),
  ADD KEY `emailverifycode` (`emailverifycode`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `domain_files`
--
ALTER TABLE `domain_files`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `dsmail`
--
ALTER TABLE `dsmail`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `file_database`
--
ALTER TABLE `file_database`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `iptable`
--
ALTER TABLE `iptable`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `textspace`
--
ALTER TABLE `textspace`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `transactions`
--
ALTER TABLE `transactions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
