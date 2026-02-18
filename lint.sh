#!/bin/bash

# =============================================================================
# Godot Project Linter
# =============================================================================
# Comprehensive linting tool that checks for:
# 1. File/folder naming convention violations
# 2. GDScript static analysis issues (gdlint)
# 3. Summary and actionable recommendations
# =============================================================================

set -e

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Unicode symbols
CHECK="✓"
CROSS="✗"
WARN="⚠"
INFO="ℹ"
ROCKET="🚀"
TOOLS="🔧"
CHART="📊"
FOLDER="📁"
FILE="📄"

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                                                                           ║${NC}"
    echo -e "${BOLD}${BLUE}║${NC}  ${ROCKET}  ${BOLD}${CYAN}GODOT PROJECT LINTER${NC}${BLUE}                                             ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}║                                                                           ║${NC}"
    echo -e "${BOLD}${BLUE}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${MAGENTA}  $1${NC}"
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_subsection() {
    echo ""
    echo -e "${BOLD}${CYAN}▶ $1${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}${CHECK}${NC} $1"
}

print_error() {
    echo -e "${RED}${CROSS}${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}${WARN}${NC} $1"
}

print_info() {
    echo -e "${CYAN}${INFO}${NC} $1"
}

print_stat() {
    local label=$1
    local value=$2
    local color=$3
    printf "  ${BOLD}%-35s${NC} ${color}%s${NC}\n" "$label:" "$value"
}

print_command() {
    echo -e "${DIM}  $ ${BOLD}$1${NC}"
}

# =============================================================================
# Naming Convention Checks
# =============================================================================

check_naming_conventions() {
    print_section "${FOLDER} FILE & FOLDER NAMING CONVENTIONS"

    local naming_script="tools/renamer/naming_convention_fixer.py"
    local report_file=$(mktemp)

    if [ ! -f "$naming_script" ]; then
        print_warning "Naming convention checker not found at: $naming_script"
        print_info "Skipping naming convention checks..."
        return 0
    fi

    print_info "Scanning project for naming violations..."
    echo ""

    # Run the naming convention checker and capture output
    if python3 "$naming_script" --report > "$report_file" 2>&1; then
        # Count total violations (lines with "Found:")
        local total_violations=$(grep -c "Found:" "$report_file" 2>/dev/null || echo "0")

        # Count violations by category
        local scenes_violations=$(grep "scenes_" "$report_file" | grep -o "[0-9]* violations" | awk '{sum += $1} END {print sum+0}')
        local scripts_violations=$(grep "scripts_" "$report_file" | grep -o "[0-9]* violations" | awk '{sum += $1} END {print sum+0}')
        local assets_violations=$(grep "assets_" "$report_file" | grep -o "[0-9]* violations" | awk '{sum += $1} END {print sum+0}')

        # Display statistics
        print_stat "Total Violations" "$total_violations" "${RED}"
        if [ "$scenes_violations" -gt 0 ] || [ "$scripts_violations" -gt 0 ] || [ "$assets_violations" -gt 0 ]; then
            print_stat "├─ Scenes Violations" "$scenes_violations" "${YELLOW}"
            print_stat "├─ Scripts Violations" "$scripts_violations" "${YELLOW}"
            print_stat "└─ Assets Violations" "$assets_violations" "${YELLOW}"
        fi
        echo ""

        if [ "$total_violations" -eq 0 ]; then
            print_success "No naming convention violations found!"
        else
            print_warning "$total_violations naming convention violations detected"
            echo ""
            echo -e "${DIM}Sample violations (first 10):${NC}"
            echo ""
            # Show first 10 violations from the report
            grep "Found:" "$report_file" | head -n 10 | sed 's/^    Found: /  /' || true
            echo ""
            if [ "$total_violations" -gt 10 ]; then
                echo -e "${DIM}  ... and $((total_violations - 10)) more${NC}"
                echo ""
            fi
        fi
    else
        print_error "Failed to run naming convention checker"
        cat "$report_file"
    fi

    rm -f "$report_file"
}

# =============================================================================
# GDScript Static Analysis
# =============================================================================

check_gdlint() {
    print_section "${FILE} GDSCRIPT STATIC ANALYSIS (gdlint)"

    if ! command -v gdlint &> /dev/null; then
        print_warning "gdlint not found. Install with: pip install gdtoolkit"
        print_info "Skipping GDScript static analysis..."
        return 0
    fi

    print_info "Running gdlint on all GDScript files..."
    echo ""

    local gdlint_output=$(mktemp)
    local gdlint_summary=$(mktemp)

    # Run gdlint and capture output
    if gdlint scripts/ scenes/ 2>&1 | tee "$gdlint_output"; then
        local exit_code=0
    else
        local exit_code=$?
    fi

    # Count violations by type (strip whitespace and ensure integer)
    local total_issues=$(grep -c "Error:" "$gdlint_output" 2>/dev/null | tr -d '\n\r' || echo "0")
    total_issues=${total_issues:-0}
    local function_name=$(grep -c "function-name" "$gdlint_output" 2>/dev/null | tr -d '\n\r' || echo "0")
    function_name=${function_name:-0}
    local class_name=$(grep -c "class-name" "$gdlint_output" 2>/dev/null | tr -d '\n\r' || echo "0")
    class_name=${class_name:-0}
    local variable_name=$(grep -c "variable-name" "$gdlint_output" 2>/dev/null | tr -d '\n\r' || echo "0")
    variable_name=${variable_name:-0}
    local constant_name=$(grep -c "constant-name" "$gdlint_output" 2>/dev/null | tr -d '\n\r' || echo "0")
    constant_name=${constant_name:-0}
    local max_line_length=$(grep -c "max-line-length" "$gdlint_output" 2>/dev/null | tr -d '\n\r' || echo "0")
    max_line_length=${max_line_length:-0}
    local trailing_whitespace=$(grep -c "trailing-whitespace" "$gdlint_output" 2>/dev/null | tr -d '\n\r' || echo "0")
    trailing_whitespace=${trailing_whitespace:-0}
    local unused_argument=$(grep -c "unused-argument" "$gdlint_output" 2>/dev/null | tr -d '\n\r' || echo "0")
    unused_argument=${unused_argument:-0}
    local private_method_call=$(grep -c "private-method-call" "$gdlint_output" 2>/dev/null | tr -d '\n\r' || echo "0")
    private_method_call=${private_method_call:-0}

    # Display statistics
    print_stat "Total Issues" "$total_issues" "${RED}"
    echo ""

    if [ "$total_issues" -gt 0 ]; then
        echo -e "${BOLD}${CYAN}Issue Breakdown:${NC}"
        echo ""

        if [ "$function_name" -gt 0 ]; then print_stat "├─ Function Naming" "$function_name" "${YELLOW}"; fi
        if [ "$class_name" -gt 0 ]; then print_stat "├─ Class Naming" "$class_name" "${YELLOW}"; fi
        if [ "$variable_name" -gt 0 ]; then print_stat "├─ Variable Naming" "$variable_name" "${YELLOW}"; fi
        if [ "$constant_name" -gt 0 ]; then print_stat "├─ Constant Naming" "$constant_name" "${YELLOW}"; fi
        if [ "$max_line_length" -gt 0 ]; then print_stat "├─ Line Length" "$max_line_length" "${YELLOW}"; fi
        if [ "$trailing_whitespace" -gt 0 ]; then print_stat "├─ Trailing Whitespace" "$trailing_whitespace" "${YELLOW}"; fi
        if [ "$private_method_call" -gt 0 ]; then print_stat "├─ Private Method Calls" "$private_method_call" "${YELLOW}"; fi
        if [ "$unused_argument" -gt 0 ]; then print_stat "└─ Unused Arguments" "$unused_argument" "${YELLOW}"; fi
        echo ""

        print_warning "$total_issues static analysis issues detected"
        echo ""
        echo -e "${DIM}Sample issues (first 15):${NC}"
        echo ""
        grep "Error:" "$gdlint_output" | head -n 15 || true
        echo ""
        if [ "$total_issues" -gt 15 ]; then
            echo -e "${DIM}  ... and $((total_issues - 15)) more${NC}"
            echo ""
        fi
    else
        print_success "No gdlint violations found!"
    fi

    rm -f "$gdlint_output" "$gdlint_summary"
}

# =============================================================================
# Code Complexity Analysis (Optional)
# =============================================================================

check_complexity() {
    print_section "${CHART} CODE COMPLEXITY ANALYSIS (gdradon)"

    if ! command -v gdradon &> /dev/null; then
        print_warning "gdradon not found. Install with: pip install gdtoolkit"
        print_info "Skipping complexity analysis..."
        return 0
    fi

    print_info "Analyzing cyclomatic complexity..."
    echo ""

    local complexity_output=$(mktemp)

    # Run gdradon cc (cyclomatic complexity)
    if gdradon cc scripts/ scenes/ > "$complexity_output" 2>&1; then
        # Count functions with high complexity (grade C or higher: C=11-20, D=21-50, E=51-100, F=100+)
        local high_complexity=$(grep -E "^\s+F.*- [C-F] \(" "$complexity_output" | wc -l | tr -d ' ' || echo "0")
        high_complexity=${high_complexity:-0}

        print_stat "High Complexity Functions (C-F)" "$high_complexity" "${RED}"
        echo ""

        if [ "$high_complexity" -gt 0 ]; then
            print_warning "Found $high_complexity functions with high complexity (grade C or higher)"
            echo ""
            echo -e "${DIM}High complexity functions (grade C-F):${NC}"
            echo ""
            grep -E "^\s+F.*- [C-F] \(" "$complexity_output" | sed 's/^/  /' | head -n 15 || true
            echo ""
            if [ "$high_complexity" -gt 15 ]; then
                echo -e "${DIM}  ... and $((high_complexity - 15)) more${NC}"
                echo ""
            fi
        else
            print_success "All functions have acceptable complexity (grade A-B)!"
        fi
    else
        print_warning "Could not analyze complexity"
    fi

    rm -f "$complexity_output"
}

# =============================================================================
# Summary and Recommendations
# =============================================================================

print_summary() {
    print_section "${TOOLS} RECOMMENDATIONS & ACTIONS"

    echo -e "${BOLD}${CYAN}To fix GDScript static analysis issues:${NC}"
    echo ""
    print_command "gdlint scripts/path/to/file.gd"
    echo -e "${DIM}    Lint a specific file to see detailed violations${NC}"
    echo ""
    print_command "gdformat scripts/"
    echo -e "${DIM}    Auto-format all GDScript files (fixes whitespace, etc.)${NC}"
    echo ""
    print_command "gdformat scripts/path/to/file.gd"
    echo -e "${DIM}    Format a specific file${NC}"
    echo ""

    echo -e "${BOLD}${CYAN}To view code complexity:${NC}"
    echo ""
    print_command "gdradon cc scripts/"
    echo -e "${DIM}    Show cyclomatic complexity for all files${NC}"
    echo ""
    print_command "gdradon cc scripts/path/to/file.gd"
    echo -e "${DIM}    Show complexity for a specific file${NC}"
    echo ""

    echo -e "${BOLD}${CYAN}Additional resources:${NC}"
    echo ""
    print_info "See gdlintrc for gdlint configuration"
    echo ""
}

print_footer() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  Lint complete! ${GREEN}${CHECK}${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    print_header

    # Check if we're in the project root
    if [ ! -f "project.godot" ]; then
        print_error "Not in a Godot project root directory!"
        print_info "Please run this script from the project root."
        exit 1
    fi

    # Run all checks
    check_naming_conventions
    check_gdlint
    check_complexity

    # Print summary
    print_summary
    print_footer
}

# Run main function
main
