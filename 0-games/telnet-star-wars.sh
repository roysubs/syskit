# Author: Roy Wiseman 2025-02
echo "
The Telnet Star Wars (also known as telnet towel.blinkenlights.nl) is a simple ASCII animation of the Star Wars opening crawl, displayed over a Telnet connection. Unfortunately, there are no built-in controls like pause or speed adjustments in the Telnet service itself.

However, here are a few options to modify the experience:

1. Pause the Telnet Session:
You can pause the session using the Ctrl + Z shortcut in most terminals, which sends a SIGTSTP signal and pauses the running process. You can resume it by typing fg and pressing Enter.

2. Redirect Output to a File and Edit:
If you want to slow down or modify the speed of the animation, you can redirect the output to a file and manipulate the speed using tools like cat, pv, or sleep.

For example:
telnet towel.blinkenlights.nl | pv -qL 10
pv will limit the output to 10 characters per second (-L 10).
You can adjust the 10 value to a different speed to slow it down or speed it up.
The -q flag suppresses progress messages.

3. Replay the Session with Slower Speed:
You can save the Telnet output to a file and replay it with sleep intervals between lines. For example:

telnet towel.blinkenlights.nl | tee starwars.txt

Then you can replay it slowly by:
cat starwars.txt | while read -r line; do echo "$line"; sleep 0.1; done

This will print each line with a 0.1-second delay between lines, slowing down the animation. You can adjust the sleep 0.1 delay as desired.

You can speed up the animation from the website:
https://www.asciimation.co.nz/

Press any key to start:   telnet towel.blinkenlights.nl
"
read -r



telnet towel.blinkenlights.nl

# The IPv6 stuff about colors etc is a joke...
# telnet 2001:980:ffe:1::42
# You see the following if you go there:

#        Well, the IPv6 version is exactly the same as the IPv4 one.       
#        The difference is in the visitors...                              
#                                                                          
#        Je bent een Stoere Bikkel, aka You Rock.
