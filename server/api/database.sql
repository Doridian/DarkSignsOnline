-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: localhost
-- Generation Time: Apr 24, 2024 at 07:28 AM
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
-- Table structure for table `domains`
--

CREATE TABLE `domains` (
  `id` int(11) NOT NULL,
  `owner` int(11) NOT NULL,
  `ip` varchar(255) NOT NULL,
  `host` varchar(255) DEFAULT NULL,
  `regtype` enum('DOMAIN','IP','SUBDOMAIN') NOT NULL,
  `time` int(11) NOT NULL,
  `keycode` varchar(255) NOT NULL,
  `parent` int(11) DEFAULT NULL
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
  `id` int(11) NOT NULL,
  `domain` int(11) NOT NULL,
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
  `from_addr` varchar(255) NOT NULL,
  `subject` varchar(4096) NOT NULL,
  `message` longtext NOT NULL,
  `time` int(11) NOT NULL,
  `message_hash` varchar(255) NOT NULL
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
-- Table structure for table `libraries`
--

CREATE TABLE `libraries` (
  `id` int(11) NOT NULL,
  `hash` varchar(255) NOT NULL,
  `data` longtext NOT NULL,
  `owner` int(11) NOT NULL,
  `time` int(11) NOT NULL
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
-- Indexes for table `domains`
--
ALTER TABLE `domains`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `ip` (`ip`),
  ADD UNIQUE KEY `host` (`host`),
  ADD KEY `owner` (`owner`),
  ADD KEY `parent` (`parent`);

--
-- Indexes for table `domain_files`
--
ALTER TABLE `domain_files`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `domain_filename` (`domain`,`filename`) USING HASH,
  ADD KEY `domain` (`domain`);

--
-- Indexes for table `domain_scripts`
--
ALTER TABLE `domain_scripts`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `domain_port_ver` (`domain`,`port`,`ver`) USING BTREE,
  ADD KEY `id` (`domain`);

--
-- Indexes for table `dsmail`
--
ALTER TABLE `dsmail`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `message_uniqueness` (`to_user`,`from_addr`,`subject`,`message_hash`) USING HASH,
  ADD KEY `to_user` (`to_user`);

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
-- Indexes for table `libraries`
--
ALTER TABLE `libraries`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `hash` (`hash`),
  ADD KEY `owner` (`owner`);

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
-- AUTO_INCREMENT for table `domains`
--
ALTER TABLE `domains`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `domain_files`
--
ALTER TABLE `domain_files`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `domain_scripts`
--
ALTER TABLE `domain_scripts`
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
-- AUTO_INCREMENT for table `libraries`
--
ALTER TABLE `libraries`
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

--
-- Constraints for dumped tables
--

--
-- Constraints for table `domains`
--
ALTER TABLE `domains`
  ADD CONSTRAINT `domains_ibfk_1` FOREIGN KEY (`owner`) REFERENCES `users` (`id`),
  ADD CONSTRAINT `domains_ibfk_2` FOREIGN KEY (`parent`) REFERENCES `domains` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `domain_files`
--
ALTER TABLE `domain_files`
  ADD CONSTRAINT `domain_files_ibfk_1` FOREIGN KEY (`domain`) REFERENCES `domains` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `domain_scripts`
--
ALTER TABLE `domain_scripts`
  ADD CONSTRAINT `domain_scripts_ibfk_1` FOREIGN KEY (`domain`) REFERENCES `domains` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `dsmail`
--
ALTER TABLE `dsmail`
  ADD CONSTRAINT `dsmail_ibfk_2` FOREIGN KEY (`to_user`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `file_database`
--
ALTER TABLE `file_database`
  ADD CONSTRAINT `file_database_ibfk_1` FOREIGN KEY (`owner`) REFERENCES `users` (`id`);

--
-- Constraints for table `libraries`
--
ALTER TABLE `libraries`
  ADD CONSTRAINT `libraries_ibfk_1` FOREIGN KEY (`owner`) REFERENCES `users` (`id`);

--
-- Constraints for table `textspace`
--
ALTER TABLE `textspace`
  ADD CONSTRAINT `textspace_ibfk_1` FOREIGN KEY (`owner`) REFERENCES `users` (`id`);

--
-- Constraints for table `transactions`
--
ALTER TABLE `transactions`
  ADD CONSTRAINT `transactions_ibfk_1` FOREIGN KEY (`toid`) REFERENCES `users` (`id`),
  ADD CONSTRAINT `transactions_ibfk_2` FOREIGN KEY (`fromid`) REFERENCES `users` (`id`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
