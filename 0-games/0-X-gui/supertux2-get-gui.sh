#!/bin/bash
# Author: Roy Wiseman 2025-05

echo "A classic 2D platformer inspired by Super Mario, featuring Tux the penguin. It offers colorful graphics and smooth gameplay, making it a great choice for casual gaming."
echo "Confusingly, the apt package is supertux, but the binary is supertux2"
echo "Works well with WSL in Windows (with WSLg)"

sudo apt install supertux
sudo ln -s /usr/games/supertux2 /usr/games/supertux
sudo ln -s /usr/games/supertux2 /usr/games/supertux2
