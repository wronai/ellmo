#!/bin/bash

# Install git hooks
echo "Installing git hooks..."
mkdir -p .git/hooks

echo '#!/bin/bash
make format' > .git/hooks/pre-commit

chmod +x .git/hooks/pre-commit
echo -e "\033[0;32m✓ Git hooks installed\033[0m"
