#!/bin/bash
# Author: Roy Wiseman 2025-01

echo "
SLASH'EM
########

Slash'em is a Nethack variant

   This is SuperLotsoAddedStuffHack-Extended Magic 1997-2006
   NetHack, Copyright 1985-2003 Stichting Mathematisch Centrum, M. Stephenson.
   See license for details. Bug reports to slashem-discuss@lists.sourceforge.net


SLASH'EM stands for "Super Lotsa Added Stuff Hack - Extended Magic," and that name is quite accurate. It significantly expands upon the base NetHack game in numerous ways. Here are some of the key differences:

More Content: This is the most apparent difference. SLASH'EM adds a wealth of new:

Races and Roles: More options for character creation, often with unique abilities and playstyles.
Monsters: A greatly expanded bestiary, including more challenging and sometimes surprising foes.
Items and Artifacts: Many new weapons, armor, rings, amulets, tools, and powerful unique artifacts with diverse effects. This includes less traditional items like firearms and lightsabers.
Dungeon Levels and Branches: The main dungeon is longer, and there are many new special levels and side branches to explore, including lairs for all the demon lords (not just some, as in vanilla NetHack).
Spells and Magic: The magic system has been extended with new spells and potentially different spell schools.
Shop Types: New types of shops, such as frozen food stores and pet stores.
Techniques: A notable addition is the "techniques" system, special abilities tied to specific roles or races that can be activated, usually with a cooldown period. This adds another layer to combat and utility.

Difficulty and Balance: SLASH'EM is generally considered more difficult than vanilla NetHack, particularly in the early game, due to the increased variety and power of monsters. However, some players find the late game can become easier with the abundance of powerful guaranteed items available in new special levels like the Black Market. The balance is often described as a bit more "kitchen sink," with a wider power curve for both the player and monsters.

New Mechanics: Beyond just more "stuff," SLASH'EM introduces some new mechanics, such as:

Different effects for things like dexterity on AC.
Changes to existing mechanics like polymorph (e.g., werecreatures reverting to human form upon death).
Moldy corpses providing potential food or intrinsics.
Drain resistance as a significant defensive category.
Shopkeeper Services: Shopkeepers may offer more varied services.

In essence, SLASH'EM takes the core NetHack experience and turns the dial up on variety and complexity. While the fundamental gameplay and most commands remain the same, the sheer volume of new elements makes it a distinct and often more challenging game.


SLASH'EM Command Summary (ASCII)

---------------------------------------------------------------------------
| ESSENTIAL / MOVEMENT        | ACTIONS / ITEMS                           |
---------------------------------------------------------------------------
| S     Save game             | w     Wield weapon                        |
| ^C    Quit game (+ prompt)  | x     Exchange weapons                    |
|       or #quit              |                                           |
| h j k l Move (left/down/up/ | P     Put on ring                         |
|       right)                | R     Remove ring                         |
| y u b n Move (diagonals)    |                                           |
| H J K L Run (left/down/up/  | a     Apply item or action                |
|       right)                | z     Zap wand                            |
| Y U B N Run (diagonals)     | E     Engrave                             |
| . or 5 Wait a turn          |                                           |
| ; or : Look around          | >     Go down stairs                      |
| s     Search for secret     | <     Go up stairs                        |
|       doors/traps           |                                           |
| i     Inventory             | ^D    Kick (Ctrl+D)                       |
| , or g  Pick up item(s)     | #jump Jump                                |
| d     Drop item(s)          | #sit  Sit                                 |
| q     Quaff potion          | #rub  Rub object                          |
| r     Read scroll or book   |                                           |
| e     Eat food              | p     Pray                                |
| W     Wear armor            | #offer Offer to altar                     |
| T     Take off armor        | #dip  Dip item in fluid                   |
|                             |                                           |
|                             | ^F    Untrap (Ctrl+F)                     |
|                             | A     Adjust inventory letters/autopickup |
|                             | S     Toggle search mode                  |
|                             | O     Toggle options                      |
|                             | Z     Cast spell (if capable)             |
|                             | #chat Chat (with shopkeepers, etc.)       |
---------------------------------------------------------------------------

This is a summary of common commands. Many commands require a direction or an item selection after pressing the command key. For a full list of commands, consult the in-game help (?) or the SLASH'EM documentation.

There are 3 variants of SLASH'EM:
sudo apt install slashem       # for console
sudo apt install slashem-sdl   # for SDL graphical interface
sudo apt install slashem-x11   # for X11 graphical interface
"
