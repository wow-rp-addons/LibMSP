# LibMSP

The **Mary Sue Protocol** is a common protocol for World of Warcraft roleplaying add-ons to communicate with each others in order to send user data such as roleplay profiles.

It is a simple challenge/response protocol, where a client send request to another client to pull data. It includes versioning for individual fields, group requests for tooltip data, and a throttle to avoid excessive communication

## Documentation

The original documentation from Etarna for LibMSP is available [on this repository wiki](https://github.com/Ellypse/LibMSP/wiki/Original-Mary-Sue-Protocol-documentation) or on [https://moonshyne.org/msp/](https://moonshyne.org/msp/)

## Known add-ons that are implementing the Mary Sue Protocol

- [GnomTEC Badge](https://wow.curseforge.com/projects/gnomtec_badge)
- [MyRolePlay](https://wow.curseforge.com/projects/my-role-play)
- [Total RP 3](https://wow.curseforge.com/projects/total-rp-3)
- [VERS Addon](https://wow.curseforge.com/projects/vers-addon)
- [XRP](https://wow.curseforge.com/projects/xrp)

You can also check Townlong Yak's Globe tool to see which add-ons are writting or reading the LibMSP's global variable [https://www.townlong-yak.com/globe/wut/#q:msp](https://www.townlong-yak.com/globe/wut/#q:msp)
