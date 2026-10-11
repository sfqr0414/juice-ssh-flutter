-- table (25)
-- android_metadata
CREATE TABLE android_metadata (locale TEXT);
-- configfield
CREATE TABLE `configfield` (`defaultValue` VARCHAR , `name` VARCHAR , `encrypted` VARCHAR , `id` VARCHAR , `isEncrypted` SMALLINT , `lastUpdatedBy_id` VARCHAR , `modified` BIGINT , `owner_id` VARCHAR , PRIMARY KEY (`id`) );
-- configvalue
CREATE TABLE `configvalue` (`field_id` VARCHAR , `value` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- connection
CREATE TABLE `connection` (`group_id` VARCHAR , `via_id` VARCHAR , `nickname` VARCHAR , `address` VARCHAR , `snippet_id` VARCHAR , `mosh_command` VARCHAR , `port` INTEGER , `type` INTEGER , `backspaceMode` INTEGER , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- connectioncounter
CREATE TABLE `connectioncounter` (`connection_id` VARCHAR , `count` INTEGER , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- connectiongroup
CREATE TABLE `connectiongroup` (`name` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- connectiongroupmembership
CREATE TABLE `connectiongroupmembership` (`group_id` VARCHAR , `connection_id` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- connectionidentity
CREATE TABLE `connectionidentity` (`connection_id` VARCHAR , `identity_id` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- deleteditem
CREATE TABLE `deleteditem` (`id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- ec2connection
CREATE TABLE `ec2connection` (`mapping_id` VARCHAR , `instanceId` VARCHAR , `group_id` VARCHAR , `via_id` VARCHAR , `nickname` VARCHAR , `address` VARCHAR , `snippet_id` VARCHAR , `mosh_command` VARCHAR , `port` INTEGER , `type` INTEGER , `backspaceMode` INTEGER , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- ec2filter
CREATE TABLE `ec2filter` (`mapping_id` VARCHAR , `key` VARCHAR , `pattern` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- ec2groupmapping
CREATE TABLE `ec2groupmapping` (`mapping_id` VARCHAR , `group_id` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- ec2mapping
CREATE TABLE `ec2mapping` (`profile_id` VARCHAR , `defaultType` INTEGER , `defaultIdentity_id` VARCHAR , `defaultConnectVia_id` VARCHAR , `privateIps` SMALLINT , `defaultPort` INTEGER , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- ec2profile
CREATE TABLE `ec2profile` (`name` VARCHAR , `region` VARCHAR , `key` VARCHAR , `secret` VARCHAR , `isEnabled` SMALLINT , `disabledReason` VARCHAR , `lastSyncTime` BIGINT , `lastSyncItemCount` INTEGER , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- host
CREATE TABLE `host` (`hostname` VARCHAR , `fingerprint` VARCHAR , `key` VARCHAR , `type` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- identity
CREATE TABLE `identity` (`username` VARCHAR , `password` VARCHAR , `privatekey` VARCHAR , `privatekeyPassword` VARCHAR , `nickname` VARCHAR , `passUpdated` BIGINT , `keyUpdated` BIGINT , `snippet_id` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- plugin_log
CREATE TABLE `plugin_log` (`packageName` VARCHAR , `message` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- portforward
CREATE TABLE `portforward` (`name` VARCHAR , `mode` INTEGER , `connection_id` VARCHAR , `host` VARCHAR , `localPort` INTEGER , `remotePort` INTEGER , `openInBrowser` SMALLINT , `useAsProxy` SMALLINT , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- purchase
CREATE TABLE `purchase` (`user_id` VARCHAR , `product` VARCHAR , `state` INTEGER , `time` BIGINT , `order` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- share
CREATE TABLE `share` (`group_id` VARCHAR , `team_id` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- snippet
CREATE TABLE `snippet` (`name` VARCHAR , `content` VARCHAR , `count` INTEGER , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- team
CREATE TABLE `team` (`name` VARCHAR , `encryptionTest` VARCHAR , `passUpdated` BIGINT , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- teamencryption
CREATE TABLE `teamencryption` (`team_id` VARCHAR , `item` VARCHAR , `revision` BIGINT , `type` VARCHAR , `data` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- teammembership
CREATE TABLE `teammembership` (`user_id` VARCHAR , `team_id` VARCHAR , `email` VARCHAR , `notified` SMALLINT , `accepted` SMALLINT , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );
-- user
CREATE TABLE `user` (`name` VARCHAR , `given_name` VARCHAR , `family_name` VARCHAR , `email` VARCHAR , `picture` VARCHAR , `signature` VARCHAR , `disabled` SMALLINT , `sessionIdentifier` VARCHAR , `sessionExpires` BIGINT , `encryptionTest` VARCHAR , `passwordUpdated` BIGINT , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) );

-- index (40)
-- configfield_id_idx
CREATE INDEX `configfield_id_idx` ON `configfield` ( `id` );
-- configfield_name_idx
CREATE INDEX `configfield_name_idx` ON `configfield` ( `name` );
-- configvalue_id_idx
CREATE INDEX `configvalue_id_idx` ON `configvalue` ( `id` );
-- connection_id_idx
CREATE INDEX `connection_id_idx` ON `connection` ( `id` );
-- connectioncounter_connection_idx
CREATE INDEX `connectioncounter_connection_idx` ON `connectioncounter` ( `connection_id` );
-- connectioncounter_id_idx
CREATE INDEX `connectioncounter_id_idx` ON `connectioncounter` ( `id` );
-- connectiongroup_id_idx
CREATE INDEX `connectiongroup_id_idx` ON `connectiongroup` ( `id` );
-- connectiongroupmembership_connection_idx
CREATE INDEX `connectiongroupmembership_connection_idx` ON `connectiongroupmembership` ( `connection_id` );
-- connectiongroupmembership_group_idx
CREATE INDEX `connectiongroupmembership_group_idx` ON `connectiongroupmembership` ( `group_id` );
-- connectiongroupmembership_id_idx
CREATE INDEX `connectiongroupmembership_id_idx` ON `connectiongroupmembership` ( `id` );
-- connectionidentity_connection_idx
CREATE INDEX `connectionidentity_connection_idx` ON `connectionidentity` ( `connection_id` );
-- connectionidentity_id_idx
CREATE INDEX `connectionidentity_id_idx` ON `connectionidentity` ( `id` );
-- connectionidentity_identity_idx
CREATE INDEX `connectionidentity_identity_idx` ON `connectionidentity` ( `identity_id` );
-- deleteditem_id_idx
CREATE INDEX `deleteditem_id_idx` ON `deleteditem` ( `id` );
-- ec2connection_id_idx
CREATE INDEX `ec2connection_id_idx` ON `ec2connection` ( `id` );
-- ec2connection_mapping_idx
CREATE INDEX `ec2connection_mapping_idx` ON `ec2connection` ( `mapping_id` );
-- ec2filter_id_idx
CREATE INDEX `ec2filter_id_idx` ON `ec2filter` ( `id` );
-- ec2filter_mapping_idx
CREATE INDEX `ec2filter_mapping_idx` ON `ec2filter` ( `mapping_id` );
-- ec2groupmapping_group_idx
CREATE INDEX `ec2groupmapping_group_idx` ON `ec2groupmapping` ( `group_id` );
-- ec2groupmapping_id_idx
CREATE INDEX `ec2groupmapping_id_idx` ON `ec2groupmapping` ( `id` );
-- ec2groupmapping_mapping_idx
CREATE INDEX `ec2groupmapping_mapping_idx` ON `ec2groupmapping` ( `mapping_id` );
-- ec2mapping_defaultConnectVia_idx
CREATE INDEX `ec2mapping_defaultConnectVia_idx` ON `ec2mapping` ( `defaultConnectVia_id` );
-- ec2mapping_defaultIdentity_idx
CREATE INDEX `ec2mapping_defaultIdentity_idx` ON `ec2mapping` ( `defaultIdentity_id` );
-- ec2mapping_defaultType_idx
CREATE INDEX `ec2mapping_defaultType_idx` ON `ec2mapping` ( `defaultType` );
-- ec2mapping_id_idx
CREATE INDEX `ec2mapping_id_idx` ON `ec2mapping` ( `id` );
-- ec2mapping_profile_idx
CREATE INDEX `ec2mapping_profile_idx` ON `ec2mapping` ( `profile_id` );
-- ec2profile_id_idx
CREATE INDEX `ec2profile_id_idx` ON `ec2profile` ( `id` );
-- host_id_idx
CREATE INDEX `host_id_idx` ON `host` ( `id` );
-- identity_id_idx
CREATE INDEX `identity_id_idx` ON `identity` ( `id` );
-- plugin_log_id_idx
CREATE INDEX `plugin_log_id_idx` ON `plugin_log` ( `id` );
-- portforward_id_idx
CREATE INDEX `portforward_id_idx` ON `portforward` ( `id` );
-- purchase_id_idx
CREATE INDEX `purchase_id_idx` ON `purchase` ( `id` );
-- share_group_idx
CREATE INDEX `share_group_idx` ON `share` ( `group_id` );
-- share_id_idx
CREATE INDEX `share_id_idx` ON `share` ( `id` );
-- share_team_idx
CREATE INDEX `share_team_idx` ON `share` ( `team_id` );
-- snippet_id_idx
CREATE INDEX `snippet_id_idx` ON `snippet` ( `id` );
-- team_id_idx
CREATE INDEX `team_id_idx` ON `team` ( `id` );
-- teamencryption_id_idx
CREATE INDEX `teamencryption_id_idx` ON `teamencryption` ( `id` );
-- teammembership_id_idx
CREATE INDEX `teammembership_id_idx` ON `teammembership` ( `id` );
-- user_id_idx
CREATE INDEX `user_id_idx` ON `user` ( `id` );
