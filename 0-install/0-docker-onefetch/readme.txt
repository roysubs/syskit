The compiled versions currently on the github use GLIBC 2.39 which we can't use without breaking the host OS.
We could manually cargo compile this:
#   git clone https://github.com/o2sh/onefetch.git
#   cd onefetch
#   cargo build --release
# The compiled binary would then be in target/release/onefetch.

But this took 17 minutes on my old Microserver N36L

So, this is a proof of concept to see if it would work. We create a container for a Linux that does contain
GLIBC 2.39 and setup onefetch in there, and then have a script that starts a container with a mounted volume
at the root of a git project and then runs the onefetch inside that container against the git proect in the
mounted volume to get around the GLIBC 2.39 issue.

We used Ubuntu 24.04 for this (could also maybe use 25.04 Plucky Puffin)
