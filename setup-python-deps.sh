#!/bin/bash

# Setup script for Python dependencies
# This script checks and installs required Python packages for generate-jira-comment.py

set -e

# Colors
BLUE='\033[94m'
GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
NC='\033[0m'

echo -e "${BLUE}🔧 Setting up Python dependencies for Jira comment generation${NC}"
echo ""

# Check Python 3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python 3 is not installed${NC}"
    echo -e "${YELLOW}💡 Install Python 3 with: brew install python3${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Python 3 found: $(python3 --version)${NC}"

# Check if requests module is installed
if python3 -c "import requests" 2>/dev/null; then
    echo -e "${GREEN}✓ requests module already installed${NC}"
    echo ""
    echo -e "${GREEN}🎉 All dependencies are installed!${NC}"
    exit 0
fi

echo -e "${YELLOW}⚠️  requests module not found${NC}"
echo ""
echo -e "${BLUE}📦 Installing requests module...${NC}"

# Try different installation methods
INSTALL_SUCCESS=false

# Method 1: Try with --break-system-packages (recommended for brew Python)
echo -e "${BLUE}Trying: pip3 install --break-system-packages requests${NC}"
if pip3 install --break-system-packages requests 2>/dev/null; then
    INSTALL_SUCCESS=true
else
    # Method 2: Try with --user flag
    echo -e "${BLUE}Trying: pip3 install --user requests${NC}"
    if pip3 install --user requests 2>/dev/null; then
        INSTALL_SUCCESS=true
    else
        # Method 3: Try without any flags
        echo -e "${BLUE}Trying: pip3 install requests${NC}"
        if pip3 install requests 2>/dev/null; then
            INSTALL_SUCCESS=true
        fi
    fi
fi

if [ "$INSTALL_SUCCESS" = true ]; then
    echo ""
    echo -e "${GREEN}✓ requests module installed successfully!${NC}"
    echo ""
    echo -e "${GREEN}🎉 Setup complete! Natural Jira comments are now available.${NC}"
else
    echo ""
    echo -e "${RED}❌ Automatic installation failed${NC}"
    echo ""
    echo -e "${YELLOW}💡 Manual installation options:${NC}"
    echo ""
    echo -e "  ${YELLOW}Option 1: Install with brew (recommended)${NC}"
    echo -e "    brew install python-requests"
    echo ""
    echo -e "  ${YELLOW}Option 2: Install with pip3${NC}"
    echo -e "    pip3 install --break-system-packages requests"
    echo ""
    echo -e "  ${YELLOW}Option 3: Use virtual environment${NC}"
    echo -e "    python3 -m venv ~/venv"
    echo -e "    source ~/venv/bin/activate"
    echo -e "    pip install requests"
    echo ""
    echo -e "${YELLOW}📝 Note: The script will fall back to the bash implementation${NC}"
    echo -e "${YELLOW}   if Python dependencies are not available.${NC}"
    exit 1
fi
