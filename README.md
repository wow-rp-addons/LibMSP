# LibMSP

The **Mary Sue Protocol** is a common protocol for World of Warcraft roleplaying add-ons to communicate with each others in order to send user data such as roleplay profiles.

It is a simple challenge/response protocol, where a client send request to another client to pull data. It includes versioning for individual fields, group requests for tooltip data, and a throttle to avoid excessive communication.

## Goals for this repository

The orignal LibMSP is hosted on [its author, Etarna,'s website][official website] as a ZIP file. I found this very limiting and wanted a way for any user of the LibMSP library to participate in its improvement. I strongly encourage any developer of an RP add-on that uses the LibMSP to come here and participate, offer help and suggestions to improve the library, participate in the documentation, in hope that this repository will replace the static website as the source for the LibMSP library.

## Differences with [Etarna's version][official website]

- Too many to document at the moment, with the 8.0 rewrite.

## Documentation

The original documentation from Etarna for LibMSP is available [on this repository wiki](https://github.com/Ellypse/LibMSP/wiki/Original-Mary-Sue-Protocol-documentation)

## Known add-ons that are implementing the Mary Sue Protocol

- [GnomTEC Badge](https://wow.curseforge.com/projects/gnomtec_badge)
- [MyRolePlay](https://wow.curseforge.com/projects/my-role-play)
- [Total RP 3](https://wow.curseforge.com/projects/total-rp-3)
- [XRP](https://github.com/Itarater/XRP)

You can also check Townlong Yak's Globe tool to see which add-ons are writting or reading the LibMSP's global variable [https://www.townlong-yak.com/globe/wut/#q:msp](https://www.townlong-yak.com/globe/wut/#q:msp)

[official website]: https://moonshyne.org/msp/
