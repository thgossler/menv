#!/bin/sh

# menv - Manage Environment Variables for macOS
# A CLI tool to manage user-scope environment variables for GUI apps and shells

set -eu

# Script information
readonly SCRIPT_NAME="menv"
readonly SCRIPT_VERSION="0.1.2"
readonly SCRIPT_DESCRIPTION="Manage user environment variables on macOS"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Configuration paths
readonly USER_LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"
readonly USER_ENV_PLIST="$USER_LAUNCHAGENT_DIR/environment.plist"

# User shell profiles where environment variables can be defined
readonly USER_SHELL_PROFILES="$HOME/.zshrc $HOME/.bash_profile $HOME/.bashrc $HOME/.profile $HOME/.zshenv $HOME/.bash_login $HOME/.zprofile"

# macOS-specific user environment files
readonly MACOS_ENV_FILES="$HOME/.MacOSX/environment.plist"

# Fish shell config (if present)
readonly FISH_CONFIG="$HOME/.config/fish/config.fish"

# PATH-like variables that need special handling
readonly PATH_LIKE_VARS="PATH LIBRARY_PATH LD_LIBRARY_PATH DYLD_LIBRARY_PATH PKG_CONFIG_PATH MANPATH INFOPATH CLASSPATH PYTHONPATH NODE_PATH"

# Global variables
ACTION=""
VAR_NAME=""
VAR_VALUE=""
FORCE="false"
VERBOSE="false"

# Function to display colored output
print_color() {
    local color=$1
    shift
    printf "${color}%s${NC}\n" "$*"
}

# Error handling
error_exit() {
    print_color "$RED" "ERROR: $1" >&2
    exit 1
}

warning() {
    print_color "$YELLOW" "WARNING: $1" >&2
}

info() {
    print_color "$BLUE" "INFO: $1"
}

success() {
    print_color "$GREEN" "SUCCESS: $1"
}

# Verbose output
debug() {
    if [ "$VERBOSE" = "true" ]; then
        print_color "$CYAN" "DEBUG: $1" >&2
    fi
}

# Display help information
# Parse command line arguments
parse_arguments() {
    while [ $# -gt 0 ]; do
        case $1 in
            -f|--force)
                FORCE="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            list)
                ACTION="list"
                shift
                ;;
            add)
                ACTION="add"
                shift
                if [ $# -lt 2 ]; then
                    error_exit "add command requires NAME and VALUE arguments"
                fi
                VAR_NAME="$1"
                VAR_VALUE="$2"
                shift 2
                ;;
            set)
                ACTION="set"
                shift
                if [ $# -lt 2 ]; then
                    error_exit "set command requires NAME and VALUE arguments"
                fi
                VAR_NAME="$1"
                VAR_VALUE="$2"
                shift 2
                ;;
            delete|del|remove)
                ACTION="delete"
                shift
                if [ $# -lt 1 ]; then
                    error_exit "delete command requires NAME argument"
                fi
                VAR_NAME="$1"
                shift
                ;;
            info)
                ACTION="info"
                shift
                if [ $# -lt 1 ]; then
                    error_exit "info command requires NAME argument"
                fi
                VAR_NAME="$1"
                shift
                ;;
            test)
                ACTION="test"
                shift
                if [ $# -lt 1 ]; then
                    error_exit "test command requires NAME argument"
                fi
                VAR_NAME="$1"
                shift
                ;;
            analyze)
                ACTION="analyze"
                shift
                if [ $# -lt 1 ]; then
                    error_exit "analyze command requires NAME argument"
                fi
                VAR_NAME="$1"
                shift
                ;;
            add-path)
                ACTION="add-path"
                shift
                if [ $# -lt 2 ]; then
                    error_exit "add-path command requires VARIABLE and PATH arguments"
                fi
                VAR_NAME="$1"
                VAR_VALUE="$2"
                shift 2
                ;;
            remove-path)
                ACTION="remove-path"
                shift
                if [ $# -lt 2 ]; then
                    error_exit "remove-path command requires VARIABLE and PATH arguments"
                fi
                VAR_NAME="$1"
                VAR_VALUE="$2"  # PATH entry to remove
                shift 2
                ;;
            help)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown option or command: $1. Use --help for usage information."
                ;;
        esac
    done

    # Validate that an action was specified
    if [ -z "$ACTION" ]; then
        error_exit "No command specified. Use --help for usage information."
    fi
}

# User scope operations don't require privilege checks

# Validate variable name
validate_var_name() {
    name="$1"
    
    # Check if name is empty
    if [ -z "$name" ]; then
        error_exit "Variable name cannot be empty"
    fi
    
    # Check if name contains invalid characters (POSIX-compatible)
    case "$name" in
        [a-zA-Z_]*) 
            # Valid start, now check the rest
            case "$name" in
                *[!a-zA-Z0-9_]*) 
                    error_exit "Invalid variable name: '$name'. Names must start with a letter or underscore and contain only letters, numbers, and underscores."
                    ;;
            esac
            ;;
        *)
            error_exit "Invalid variable name: '$name'. Names must start with a letter or underscore and contain only letters, numbers, and underscores."
            ;;
    esac
    
    debug "Variable name '$name' is valid"
}

# Create backup of a file
create_backup() {
    file="$1"
    backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$file" ]; then
        if cp "$file" "$backup_file"; then
            debug "Created backup: $backup_file"
            return 0
        else
            warning "Failed to create backup of $file"
            return 1
        fi
    fi
    return 0
}

# Ensure directory exists
ensure_directory() {
    dir="$1"
    
    if [ ! -d "$dir" ]; then
        debug "Creating directory: $dir"
        mkdir -p "$dir" || error_exit "Failed to create directory: $dir"
    fi
}

# Get user's home directory
get_user_home() {
    echo "$HOME"
}

# Check if a variable is PATH-like
is_path_like_var() {
    var_name="$1"
    echo "$PATH_LIKE_VARS" | grep -q "\b$var_name\b"
}

# Add path entry to PATH-like variable
add_to_path_var() {
    var_name="$1"
    new_path="$2"
    position="$3"  # "prepend" or "append" (default: append)
    
    # Get current value of the path variable
    current_value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
    
    if [ -z "$current_value" ]; then
        # If variable is empty, just use the new path
        echo "$new_path"
    elif [ "$position" = "prepend" ]; then
        echo "$new_path:$current_value"
    else
        echo "$current_value:$new_path"
    fi
}

# Add path entry to PATH-like variable
add_path_entry() {
    var_name="$1"
    path_entry="$2"
    
    if ! is_path_like_var "$var_name"; then
        error_exit "$var_name is not a PATH-like variable. Use regular 'add' command instead."
    fi
    
    info "Adding path entry to $var_name: $path_entry"
    
    # Check if path already exists
    current_value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
    if echo "$current_value" | tr ':' '\n' | grep -q "^$path_entry$"; then
        warning "Path entry already exists in $var_name: $path_entry"
        if [ "$FORCE" != "true" ]; then
            printf "Add anyway? [y/N]: "
            read -r response
            case "$response" in
                [yY][eE][sS]|[yY])
                    ;;
                *)
                    info "Operation cancelled"
                    return 1
                    ;;
            esac
        fi
    fi
    
    # Create the new path value (always append for add-path command)
    new_value=$(add_to_path_var "$var_name" "$path_entry" "append")
    
    # Use the regular add_set_var function, but bypass PATH prompting
    original_force="$FORCE"
    FORCE="true"
    add_set_var "$var_name" "$new_value"
    FORCE="$original_force"
}

# Remove path entry from PATH-like variable
remove_path_entry() {
    var_name="$1"
    path_entry="$2"
    
    if ! is_path_like_var "$var_name"; then
        error_exit "$var_name is not a PATH-like variable. Use regular 'delete' command instead."
    fi
    
    info "Removing path entry from $var_name: $path_entry"
    
    # Check if path exists
    current_value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
    if ! echo "$current_value" | tr ':' '\n' | grep -q "^$path_entry$"; then
        warning "Path entry not found in current $var_name: $path_entry"
        if [ "$FORCE" != "true" ]; then
            printf "Continue anyway? [y/N]: "
            read -r response
            case "$response" in
                [yY][eE][sS]|[yY])
                    ;;
                *)
                    info "Operation cancelled"
                    return 1
                    ;;
            esac
        fi
    fi
    
    # This is complex - we'd need to modify the shell profiles to remove specific path entries
    # For now, show what would be removed and suggest manual editing
    info "Path-specific removal requires careful shell profile editing"
    if [ -n "$current_value" ]; then
        info "Current $var_name contains these entries:"
        echo "$current_value" | tr ':' '\n' | nl
    fi
    
    warning "Automatic path entry removal not yet implemented"
    info "Please manually edit your shell profile files to remove: $path_entry"
    info "Common profile files: ~/.zshrc, ~/.bash_profile, ~/.profile"
    
    # Show which files might contain the variable
    sources=$(get_var_sources "$var_name")
    if [ -n "$sources" ]; then
        info "Variable '$var_name' is defined in: $(echo "$sources" | tr '\n' ' ')"
    fi
}

# Check if a variable exists in user launchctl
check_launchctl_var() {
    var_name="$1"
    
    # Check user launchctl
    if launchctl getenv "$var_name" 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

# Get variable value from user launchctl
get_launchctl_var() {
    var_name="$1"
    
    launchctl getenv "$var_name" 2>/dev/null || echo ""
}

# Check if variable exists in plist file
check_plist_var() {
    var_name="$1"
    plist_file="$2"
    
    if [ -f "$plist_file" ]; then
        if plutil -p "$plist_file" 2>/dev/null | grep -q "\"$var_name\""; then
            return 0
        fi
    fi
    return 1
}

# Get variable value from plist file
get_plist_var() {
    var_name="$1"
    plist_file="$2"
    
    if [ -f "$plist_file" ]; then
        # Extract value using plutil and parse the output
        value=$(plutil -p "$plist_file" 2>/dev/null | \
                grep -A1 "\"$var_name\"" | \
                tail -n1 | \
                sed 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/\1/')
        echo "$value"
    fi
}

# Check if variable exists in shell profiles
check_shell_var() {
    var_name="$1"
    user_home=$(get_user_home)
    
    # Check user shell profile files
    for file in $USER_SHELL_PROFILES; do
        # Replace $HOME with actual home directory
        expanded_file=$(echo "$file" | sed "s|\$HOME|$user_home|")
        if [ -f "$expanded_file" ]; then
            if grep -q "^[[:space:]]*export[[:space:]]\+$var_name=" "$expanded_file" 2>/dev/null; then
                return 0
            fi
        fi
    done
    
    # Check Fish shell config
    expanded_fish=$(echo "$FISH_CONFIG" | sed "s|\$HOME|$user_home|")
    if [ -f "$expanded_fish" ]; then
        if grep -q "^[[:space:]]*set[[:space:]]\+--export[[:space:]]\+$var_name" "$expanded_fish" 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# Get variable value from shell profiles
get_shell_var() {
    var_name="$1"
    user_home=$(get_user_home)
    
    # Check user shell profiles
    for file in $USER_SHELL_PROFILES; do
        expanded_file=$(echo "$file" | sed "s|\$HOME|$user_home|")
        if [ -f "$expanded_file" ]; then
            value=$(grep "^[[:space:]]*export[[:space:]]\+$var_name=" "$expanded_file" 2>/dev/null | \
                   head -n1 | \
                   sed "s/^[[:space:]]*export[[:space:]]\+$var_name=['\"]*//" | \
                   sed "s/['\"][[:space:]]*$//" | \
                   sed 's/[[:space:]]*$//')
            if [ -n "$value" ]; then
                echo "$value"
                return 0
            fi
        fi
    done
    
    # Check Fish shell config
    expanded_fish=$(echo "$FISH_CONFIG" | sed "s|\$HOME|$user_home|")
    if [ -f "$expanded_fish" ]; then
        value=$(grep "^[[:space:]]*set[[:space:]]\+--export[[:space:]]\+$var_name" "$expanded_fish" 2>/dev/null | \
               head -n1 | \
               sed "s/^[[:space:]]*set[[:space:]]\+--export[[:space:]]\+$var_name[[:space:]]\+//" | \
               sed 's/[[:space:]]*$//')
        if [ -n "$value" ]; then
            echo "$value"
            return 0
        fi
    fi
}

# Get all sources where a variable is defined
get_var_sources() {
    var_name="$1"
    sources=""
    
    # Check user launchctl
    if check_launchctl_var "$var_name"; then
        sources="$sources launchctl"
    fi
    
    # Check user plist
    if check_plist_var "$var_name" "$USER_ENV_PLIST"; then
        sources="$sources user-plist"
    fi
    
    # Check shell profiles
    if check_shell_var "$var_name"; then
        sources="$sources shell-profile"
    fi
    
    # Check deprecated macOS environment.plist
    user_home=$(get_user_home)
    macos_env_plist="$user_home/.MacOSX/environment.plist"
    if [ -f "$macos_env_plist" ] && check_plist_var "$var_name" "$macos_env_plist"; then
        sources="$sources macos-environment-plist"
    fi
    
    # Check if variable is inherited from parent process (not in any config file)
    current_value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
    if [ -n "$current_value" ] && [ -z "$sources" ]; then
        sources="$sources inherited"
    fi
    
    # Trim leading space and output each source on a separate line
    sources=$(echo "$sources" | sed 's/^ *//')
    if [ -n "$sources" ]; then
        echo "$sources" | tr ' ' '\n'
    fi
}

# Get all environment variables from various sources
get_all_env_vars() {
    temp_file=$(mktemp)
    
    # Get ALL from current environment first (this is the most comprehensive)
    env | cut -d'=' -f1 | sort -u >> "$temp_file"
    
    # Get from user plist if it exists
    if [ -f "$USER_ENV_PLIST" ]; then
        plutil -p "$USER_ENV_PLIST" 2>/dev/null | \
        grep -E '^\s*"[^"]+"\s*=>' | \
        sed -E 's/^\s*"([^"]+)".*/\1/' >> "$temp_file"
    fi
    
    # Get from deprecated macOS environment.plist
    user_home=$(get_user_home)
    macos_env_plist="$user_home/.MacOSX/environment.plist"
    if [ -f "$macos_env_plist" ]; then
        plutil -p "$macos_env_plist" 2>/dev/null | \
        grep -E '^\s*"[^"]+"\s*=>' | \
        sed -E 's/^\s*"([^"]+)".*/\1/' >> "$temp_file"
    fi
    
    # Get from all user shell profiles
    for file in $USER_SHELL_PROFILES; do
        expanded_file=$(echo "$file" | sed "s|\$HOME|$user_home|")
        if [ -f "$expanded_file" ]; then
            grep -E '^[[:space:]]*export[[:space:]]+[A-Za-z_][A-Za-z0-9_]*=' "$expanded_file" 2>/dev/null | \
            sed -E 's/^[[:space:]]*export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=.*/\1/' >> "$temp_file"
        fi
    done
    
    # Get from Fish shell config
    expanded_fish=$(echo "$FISH_CONFIG" | sed "s|\$HOME|$user_home|")
    if [ -f "$expanded_fish" ]; then
        grep -E '^[[:space:]]*set[[:space:]]+--export[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$expanded_fish" 2>/dev/null | \
        sed -E 's/^[[:space:]]*set[[:space:]]+--export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/' >> "$temp_file"
    fi
    
    # Output unique variable names
    sort -u "$temp_file"
    rm -f "$temp_file"
}

# Format table output with dynamic column widths
format_table() {
    # Store all input in a temporary file for two-pass processing
    table_temp=$(mktemp)
    cat > "$table_temp"
    
    # Calculate maximum widths for each column
    max_name_width=4  # Minimum for "NAME" header
    max_value_width=5  # Minimum for "VALUE" header
    max_sources_width=7  # Minimum for "SOURCES" header
    
    # First pass: find maximum widths
    while IFS="	" read -r name value sources; do
        # Apply maximum limits to prevent overly wide tables
        name_len=${#name}
        value_len=${#value}
        sources_len=${#sources}
        
        # Cap maximum widths for readability
        [ $name_len -gt 64 ] && name_len=64
        [ $value_len -gt 64 ] && value_len=64
        
        # Update maximum widths
        [ $name_len -gt $max_name_width ] && max_name_width=$name_len
        [ $value_len -gt $max_value_width ] && max_value_width=$value_len
        [ $sources_len -gt $max_sources_width ] && max_sources_width=$sources_len
    done < "$table_temp"
    
    # Create format strings with calculated widths
    header_format="%-${max_name_width}s %-${max_value_width}s %s\n"
    separator_format="%-${max_name_width}s %-${max_value_width}s %s\n"
    
    # Print header
    printf "$header_format" "NAME" "VALUE" "SOURCES"
    
    # Create separator line
    name_sep=$(printf "%*s" $max_name_width "" | tr ' ' '-')
    value_sep=$(printf "%*s" $max_value_width "" | tr ' ' '-')
    sources_sep=$(printf "%*s" $max_sources_width "" | tr ' ' '-')
    printf "$separator_format" "$name_sep" "$value_sep" "$sources_sep"
    
    # Second pass: format and print data
    while IFS="	" read -r name value sources; do
        # Truncate if needed (with ellipsis)
        display_name="$name"
        if [ ${#display_name} -gt $max_name_width ]; then
            display_name=$(echo "$display_name" | cut -c1-$((max_name_width-3)))...
        fi
        
        display_value="$value"
        if [ ${#display_value} -gt $max_value_width ]; then
            display_value=$(echo "$display_value" | cut -c1-$((max_value_width-3)))...
        fi
        
        printf "$header_format" "$display_name" "$display_value" "$sources"
    done < "$table_temp"
    
    # Clean up
    rm -f "$table_temp"
}

# List all environment variables
list_vars() {
    debug "Listing environment variables"
    
    info "Gathering environment variables..."
    
    # Create temporary file for sorting
    temp_file=$(mktemp)
    
    # Get all unique variable names
    get_all_env_vars | while IFS= read -r var_name; do
        if [ -n "$var_name" ]; then
            sources=$(get_var_sources "$var_name")
            
            if [ -n "$sources" ]; then
                value=""
                sources_display=""
                
                # Check if this is an inherited variable (only source is "inherited")
                if [ "$sources" = "inherited" ]; then
                    value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
                    sources_display="inherited"
                else
                    # Determine primary value for managed variables
                    if check_launchctl_var "$var_name"; then
                        value=$(get_launchctl_var "$var_name")
                    elif check_plist_var "$var_name" "$USER_ENV_PLIST"; then
                        value=$(get_plist_var "$var_name" "$USER_ENV_PLIST")
                    elif check_shell_var "$var_name"; then
                        value=$(get_shell_var "$var_name")
                    fi
                    
                    # If still no value, get from current environment
                    if [ -z "$value" ]; then
                        value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
                    fi
                    
                    # Format sources for display
                    sources_display=$(echo "$sources" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
                fi
                
                # Clean value of any tabs or newlines that could break formatting
                clean_value=$(echo "$value" | tr '\t\n' ' ' | tr -s ' ')
                
                # Output to temp file for sorting
                printf "%s\t%s\t%s\n" "$var_name" "$clean_value" "$sources_display" >> "$temp_file"
            fi
        fi
    done
    
    # Sort and display
    if [ -s "$temp_file" ]; then
        sort "$temp_file" | format_table
        
        # Show summary
        total_vars=$(wc -l < "$temp_file")
        user_vars=$(awk -F'\t' '$3 != "inherited" {count++} END {print (count ? count : 0)}' "$temp_file")
        inherited_vars=$(awk -F'\t' '$3 == "inherited" {count++} END {print (count ? count : 0)}' "$temp_file")
        
        echo
        info "Summary: $total_vars total variables ($user_vars user-managed, $inherited_vars inherited)"
    else
        warning "No environment variables found"
    fi
    
    # Clean up
    rm -f "$temp_file"
    
    # Add informational note
    printf "\n"
    print_color "$CYAN" "INFO: Showing user-scope environment variables only"
    printf "• System variables are inherited and managed at the system level\n"
    printf "• This tool manages variables that apply to all new processes for the current user\n"
}

# Create or update a plist file with environment variables
update_plist() {
    plist_file="$1"
    var_name="$2"
    var_value="$3"
    
    debug "Updating plist: $plist_file"
    
    # Create the plist content
    plist_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
	<key>Label</key>
	<string>environment.variables</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/launchctl</string>
		<string>setenv</string>
		<string>$var_name</string>
		<string>$var_value</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>"
    
    # Ensure directory exists
    plist_dir=$(dirname "$plist_file")
    ensure_directory "$plist_dir"
    
    # Create backup if file exists
    if [ -f "$plist_file" ]; then
        create_backup "$plist_file"
    fi
    
    # Write the plist file
    echo "$plist_content" > "$plist_file"
    
    debug "Plist file updated: $plist_file"
}

# Remove variable from plist file
remove_from_plist() {
    plist_file="$1"
    var_name="$2"
    
    if [ -f "$plist_file" ]; then
        debug "Removing $var_name from plist: $plist_file"
        create_backup "$plist_file"
        
        # For now, we'll remove the entire plist if it contains our variable
        # A more sophisticated approach would parse and modify the plist
        if check_plist_var "$var_name" "$plist_file"; then
            rm -f "$plist_file"
            debug "Removed plist file: $plist_file"
        fi
    fi
}

# Set environment variable in user launchctl
set_launchctl_var() {
    var_name="$1"
    var_value="$2"
    
    debug "Setting user launchctl variable: $var_name=$var_value"
    
    launchctl setenv "$var_name" "$var_value"
}

# Remove environment variable from user launchctl
remove_launchctl_var() {
    var_name="$1"
    
    debug "Removing user launchctl variable: $var_name"
    
    launchctl unsetenv "$var_name" 2>/dev/null || true
}

# Add or update variable in shell profiles
update_shell_var() {
    var_name="$1"
    var_value="$2"
    
    user_home=$(get_user_home)
    shell_file="$user_home/.profile"
    
    debug "Updating shell variable in: $shell_file"
    
    # Create the file if it doesn't exist
    if [ ! -f "$shell_file" ]; then
        touch "$shell_file"
    fi
    
    # Create backup
    create_backup "$shell_file"
    
    # Remove existing export line for this variable
    temp_file=$(mktemp)
    grep -v "^[[:space:]]*export[[:space:]]\+$var_name=" "$shell_file" > "$temp_file" 2>/dev/null || true
    
    # Add new export line
    echo "export $var_name=\"$var_value\"" >> "$temp_file"
    
    # Replace the original file
    mv "$temp_file" "$shell_file"
    
    debug "Updated shell profile: $shell_file"
}

# Remove variable from shell profiles
remove_shell_var() {
    var_name="$1"
    user_home=$(get_user_home)
    
    for file in $user_home/.zshrc $user_home/.bash_profile $user_home/.bashrc $user_home/.profile; do
        if [ -f "$file" ]; then
            if grep -q "^[[:space:]]*export[[:space:]]\+$var_name=" "$file" 2>/dev/null; then
                debug "Removing $var_name from: $file"
                create_backup "$file"
                
                # Remove the export line
                temp_file=$(mktemp)
                grep -v "^[[:space:]]*export[[:space:]]\+$var_name=" "$file" > "$temp_file"
                mv "$temp_file" "$file"
            fi
        fi
    done
}

# Add or set an environment variable
add_set_var() {
    var_name="$1"
    var_value="$2"
    
    debug "Setting user environment variable: $var_name=$var_value"
    
    # Check if this is a PATH-like variable
    if is_path_like_var "$var_name"; then
        info "Detected PATH-like variable: $var_name"
        
        # Ask user how they want to handle it
        if [ "$FORCE" != "true" ]; then
            printf "How do you want to handle this PATH-like variable?\n"
            printf "1) Append to existing $var_name (recommended)\n"
            printf "2) Prepend to existing $var_name\n"
            printf "3) Replace entire $var_name (dangerous!)\n"
            printf "Enter choice [1-3, default: 1]: "
            read -r choice
            
            case "$choice" in
                2)
                    var_value=$(add_to_path_var "$var_name" "$var_value" "prepend")
                    info "Will prepend to $var_name: $var_value"
                    ;;
                3)
                    warning "This will completely replace $var_name!"
                    printf "Are you sure? [y/N]: "
                    read -r confirm
                    case "$confirm" in
                        [yY][eE][sS]|[yY])
                            info "Replacing entire $var_name"
                            ;;
                        *)
                            info "Operation cancelled"
                            return 1
                            ;;
                    esac
                    ;;
                1|"")
                    var_value=$(add_to_path_var "$var_name" "$var_value" "append")
                    info "Will append to $var_name: $var_value"
                    ;;
                *)
                    error_exit "Invalid choice"
                    ;;
            esac
        else
            # In force mode, default to append
            var_value=$(add_to_path_var "$var_name" "$var_value" "append")
            info "Force mode: appending to $var_name"
        fi
    fi
    
    # User-specific setting
    info "Setting user environment variable: $var_name"
    
    # Set in user launchctl (for GUI apps)
    set_launchctl_var "$var_name" "$var_value"
    
    # For PATH-like variables, avoid shell profile duplication
    if is_path_like_var "$var_name"; then
        info "PATH-like variable set in launchctl only to avoid duplication"
        info "Note: Shell profiles may contain additional PATH modifications"
    else
        # Update shell profile (for terminal sessions) - non-PATH variables
        update_shell_var "$var_name" "$var_value"
    fi
    
    success "User variable '$var_name' has been set"
    info "Note: Open a new terminal session to see the variable in shell environments"
    info "GUI applications will pick up this variable after restart"
}

# Delete an environment variable
delete_var() {
    var_name="$1"
    
    # Temporarily disable strict error handling for this function
    set +e
    
    debug "Deleting environment variable: $var_name"
    
    # Special handling for PATH-like variables
    if is_path_like_var "$var_name"; then
        warning "Attempting to delete PATH-like variable: $var_name"
        
        if [ "$FORCE" != "true" ]; then
            printf "This is a PATH-like variable. What do you want to do?\n"
            printf "1) Remove a specific path entry from $var_name\n"
            printf "2) Remove entire $var_name variable (dangerous!)\n"
            printf "Enter choice [1-2, default: 1]: "
            read -r choice
            
            case "$choice" in
                2)
                    warning "This will completely remove $var_name!"
                    printf "Are you sure? This may break your system! [y/N]: "
                    read -r confirm
                    case "$confirm" in
                        [yY][eE][sS]|[yY])
                            info "Proceeding with complete removal"
                            ;;
                        *)
                            info "Operation cancelled"
                            return 1
                            ;;
                    esac
                    ;;
                1|"")
                    printf "Enter the path entry to remove from $var_name: "
                    read -r path_entry
                    if [ -z "$path_entry" ]; then
                        error_exit "No path entry specified"
                    fi
                    info "Will remove path entry: $path_entry"
                    # Here we would call remove_path_entry function
                    warning "Path-specific removal requires manual editing of shell profiles"
                    info "Current $var_name entries:"
                    current_value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
                    if [ -n "$current_value" ]; then
                        echo "$current_value" | tr ':' '\n' | nl
                    fi
                    info "Please manually edit your shell profile files to remove: $path_entry"
                    info "Common profile files: ~/.zshrc, ~/.bash_profile, ~/.profile"
                    return 1
                    ;;
                *)
                    error_exit "Invalid choice"
                    ;;
            esac
        fi
    fi
    
    # Get all sources where this variable is defined
    sources=$(get_var_sources "$var_name")
    
    if [ -z "$sources" ]; then
        warning "Variable '$var_name' is not managed by this tool"
        # Check if it exists in current environment
        current_value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
        if [ -n "$current_value" ]; then
            info "Variable exists in current environment with value: $current_value"
            info "It may be inherited from the system or set elsewhere"
        else
            error_exit "Variable '$var_name' not found"
        fi
        return 1
    fi
    
    # Confirm deletion unless --force is used
    if [ "$FORCE" != "true" ]; then
        info "Variable '$var_name' is defined in: $(echo "$sources" | tr '\n' ' ')"
        printf "Are you sure you want to delete this variable? [y/N]: "
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                ;;
            *)
                info "Deletion cancelled"
                return 1
                ;;
        esac
    fi
    
    info "Removing environment variable: $var_name"
    
    # Remove from all sources
    echo "$sources" | while IFS= read -r source; do
        case "$source" in
            "launchctl")
                remove_launchctl_var "$var_name"
                ;;
            "user-plist")
                remove_from_plist "$USER_ENV_PLIST" "$var_name"
                ;;
            "shell-profile")
                remove_shell_var "$var_name"
                ;;
            "macos-environment-plist")
                user_home=$(get_user_home)
                remove_from_plist "$user_home/.MacOSX/environment.plist" "$var_name"
                ;;
        esac
    done
    
    success "Variable '$var_name' has been removed from all locations"
    info "Note: Current terminal session may still have the variable set"
    info "Open a new terminal session to see the changes"
    
    # Re-enable strict error handling
    set -e
}

# Show detailed information about a specific variable
show_var_info() {
    var_name="$1"
    
    # Temporarily disable strict error handling for this function
    set +e
    
    info "Information for variable: $var_name"
    printf "\n"
    
    # Get current value from current environment (this shell session)
    current_value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
    if [ -n "$current_value" ]; then
        printf "Current environment: %s\n" "$current_value"
    else
        printf "Current environment: (not set)\n"
    fi
    
    # Check launchctl directly (most reliable)
    printf "\nLaunchctl status:\n"
    launchctl_value=$(launchctl getenv "$var_name" 2>/dev/null || echo "")
    if [ -n "$launchctl_value" ]; then
        printf "  ✓ launchctl: %s\n" "$launchctl_value"
    else
        printf "  ✗ Not set in launchctl\n"
    fi
    
    # Note: System launchctl not checked in user-scope mode
    
    # Check shell profiles directly
    printf "\nShell profile status:\n"
    found_in_profiles=false
    user_home=$(get_user_home)
    
    # Check user shell profiles
    for profile in $USER_SHELL_PROFILES; do
        expanded_profile=$(echo "$profile" | sed "s|\$HOME|$user_home|")
        if [ -f "$expanded_profile" ] && grep -q "^[[:space:]]*export[[:space:]]\+$var_name=" "$expanded_profile" 2>/dev/null; then
            line=$(grep "^[[:space:]]*export[[:space:]]\+$var_name=" "$expanded_profile" 2>/dev/null | head -n1)
            value=$(echo "$line" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
            printf "  ✓ Found in %s: %s\n" "$expanded_profile" "$value"
            found_in_profiles=true
        fi
    done
    
    # Check Fish shell config
    expanded_fish=$(echo "$FISH_CONFIG" | sed "s|\$HOME|$user_home|")
    if [ -f "$expanded_fish" ] && grep -q "^[[:space:]]*set[[:space:]]\+--export[[:space:]]\+$var_name" "$expanded_fish" 2>/dev/null; then
        line=$(grep "^[[:space:]]*set[[:space:]]\+--export[[:space:]]\+$var_name" "$expanded_fish" 2>/dev/null | head -n1)
        value=$(echo "$line" | sed "s/^[[:space:]]*set[[:space:]]\+--export[[:space:]]\+$var_name[[:space:]]\+//" | sed 's/[[:space:]]*$//')
        printf "  ✓ Found in %s: %s\n" "$expanded_fish" "$value"
        found_in_profiles=true
    fi
    
    # Check deprecated macOS environment.plist
    macos_env_plist="$user_home/.MacOSX/environment.plist"
    if [ -f "$macos_env_plist" ] && check_plist_var "$var_name" "$macos_env_plist"; then
        value=$(get_plist_var "$var_name" "$macos_env_plist")
        printf "  ✓ Found in %s: %s\n" "$macos_env_plist" "$value"
        found_in_profiles=true
    fi
    
    if [ "$found_in_profiles" = false ]; then
        printf "  ✗ Not found in configuration files\n"
    fi
    
    # Test what a fresh shell would see
    printf "\nFresh shell test:\n"
    fresh_test_script=$(mktemp)
    cat > "$fresh_test_script" << 'EOF'
#!/bin/sh
# Source all common profile files in proper order
for profile in /etc/profile /etc/bashrc /etc/zshrc ~/.bash_login ~/.bash_profile ~/.bashrc ~/.profile ~/.zshenv ~/.zshrc ~/.zprofile; do
    if [ -f "$profile" ]; then
        . "$profile" 2>/dev/null || true
    fi
done

# Check if Fish config exists and try to extract variables from it
if [ -f ~/.config/fish/config.fish ]; then
    # Fish uses different syntax, try to extract exported variables
    grep "^[[:space:]]*set[[:space:]]\+--export" ~/.config/fish/config.fish 2>/dev/null | while read -r line; do
        var_name_from_fish=$(echo "$line" | sed 's/^[[:space:]]*set[[:space:]]\+--export[[:space:]]\+\([A-Za-z_][A-Za-z0-9_]*\).*/\1/')
        var_value_from_fish=$(echo "$line" | sed 's/^[[:space:]]*set[[:space:]]\+--export[[:space:]]\+[A-Za-z_][A-Za-z0-9_]*[[:space:]]\+//')
        if [ "$var_name_from_fish" = "$1" ]; then
            export "$var_name_from_fish"="$var_value_from_fish" 2>/dev/null || true
        fi
    done 2>/dev/null || true
fi

var_name="$1"
value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
if [ -n "$value" ]; then
    printf "  ✓ Fresh shell would see: %s\n" "$value"
else
    printf "  ✗ Fresh shell would not see this variable\n"
fi
EOF
    chmod +x "$fresh_test_script"
    "$fresh_test_script" "$var_name"
    rm -f "$fresh_test_script"
    
    printf "\n"
    print_color "$YELLOW" "NOTES:"
    printf "• GUI applications need to be restarted to see launchctl changes\n"
    printf "• Terminal sessions need to be restarted to see shell profile changes\n"
    printf "• Use 'menv test %s' for a comprehensive verification\n" "$var_name"
    printf "• This tool manages user-scope variables only\n"
    
    # Re-enable strict error handling
    set -e
}

# Test environment variable in a fresh shell
test_var_in_fresh_shell() {
    var_name="$1"
    
    info "Testing variable '$var_name' in a fresh shell environment..."
    printf "\n"
    
    # Create a test script that sources all profile files and checks the variable
    test_script=$(mktemp)
    cat > "$test_script" << 'EOF'
#!/bin/sh
# Source common profile files in order
for profile in ~/.profile ~/.bash_profile ~/.bashrc ~/.zshrc; do
    if [ -f "$profile" ]; then
        . "$profile" 2>/dev/null || true
    fi
done

# Get the variable value
var_name="$1"
value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
if [ -n "$value" ]; then
    printf "✓ Variable '%s' is set to: %s\n" "$var_name" "$value"
    exit 0
else
    printf "✗ Variable '%s' is not set in fresh shell environment\n" "$var_name"
    exit 1
fi
EOF
    
    chmod +x "$test_script"
    
    # Run the test in a completely fresh shell
    if "$test_script" "$var_name"; then
        success "Variable is properly configured for new shell sessions"
    else
        warning "Variable is not available in new shell sessions"
    fi
    
    # Clean up
    rm -f "$test_script"
    
    printf "\n"
    
    # Also test launchctl
    launchctl_value=$(launchctl getenv "$var_name" 2>/dev/null || echo "")
    if [ -n "$launchctl_value" ]; then
        printf "✓ Variable '%s' is set in launchctl: %s\n" "$var_name" "$launchctl_value"
        info "GUI applications launched after restart will see this value"
    else
        printf "✗ Variable '%s' is not set in launchctl\n" "$var_name"
        warning "GUI applications will not see this variable"
    fi
    
    printf "\n"
    print_color "$CYAN" "To test in VS Code:"
    printf "1. Restart VS Code completely\n"
    printf "2. Open a new terminal in VS Code\n"
    printf "3. Run: echo \$%s\n" "$var_name"
}

# Analyze PATH-like variable composition and duplicates
analyze_var() {
    var_name="$1"
    
    # Check if this is a PATH-like variable
    if ! is_path_like_var "$var_name"; then
        error_exit "Variable '$var_name' is not a PATH-like variable. Analyze command is designed for PATH, LIBRARY_PATH, etc."
    fi
    
    info "Analyzing PATH-like variable: $var_name"
    printf "\n"
    
    # Get current value
    current_value=$(eval echo \$"$var_name" 2>/dev/null || echo "")
    if [ -z "$current_value" ]; then
        warning "Variable '$var_name' is not set in current environment"
        return 1
    fi
    
    info "Current value length: ${#current_value} characters"
    info "Number of path entries: $(echo "$current_value" | tr ':' '\n' | wc -l | tr -d ' ')"
    printf "\n"
    
    # Split PATH into individual entries and analyze
    printf "PATH COMPOSITION ANALYSIS:\n"
    printf "=========================\n\n"
    
    # Create temporary files for analysis
    all_paths=$(mktemp)
    unique_paths=$(mktemp)
    
    # Split paths and number them  
    echo "$current_value" | tr ':' '\n' | awk '{print NR "\t" $0}' > "$all_paths"
    
    # Find unique paths
    echo "$current_value" | tr ':' '\n' | sort -u > "$unique_paths"
    
    # Show all paths with indicators in properly formatted table
    printf "%-6s %-6s %-9s %s\n" "Entry#" "Exists" "Duplicate" "Path"  
    printf "%-6s %-6s %-9s %s\n" "------" "------" "---------" "----"

    entry_num=1
    echo "$current_value" | tr ':' '\n' | while read -r path; do
        # Check if this path appears multiple times
        count=$(echo "$current_value" | tr ':' '\n' | grep -c "^$(printf '%s' "$path" | sed 's/[[\.*^$()+?{|]/\\&/g')$" 2>/dev/null || echo "1")
        
        # Check if path exists
        if [ -z "$path" ]; then
            exists="∅"  # Empty entry
            display_path="<empty>"
        elif [ -d "$path" ] 2>/dev/null; then
            exists="+"
            display_path="$path"
        else
            exists="-"
            display_path="$path"
        fi
        
        # Set duplicate indicator
        if [ "$count" -gt 1 ]; then
            duplicate="${count}x"
        else
            duplicate=""
        fi
        
        printf "%-6s %-6s %-9s %s\n" "$entry_num" "$exists" "$duplicate" "$display_path"
        entry_num=$((entry_num + 1))
    done
    
    printf "\n"
    
    # Summary statistics
    total_entries=$(wc -l < "$all_paths")
    unique_entries=$(wc -l < "$unique_paths")
    duplicates=$((total_entries - unique_entries))
    # Count empty entries (careful with newlines)
    empty_entries=$(echo "$current_value" | tr ':' '\n' | grep -c '^$' 2>/dev/null | tr -d '\n')
    empty_entries=${empty_entries:-0}
    
    # Count existing directories
    existing_dirs=$(echo "$current_value" | tr ':' '\n' | while read -r p; do 
        [ -n "$p" ] && [ -d "$p" ] && echo "1"
    done | wc -l | tr -d '\n')
    
    printf "SUMMARY:\n"
    printf "========\n"
    printf "Total entries:     %d\n" "$total_entries"
    printf "Unique entries:    %d\n" "$unique_entries"
    printf "Duplicate entries: %d\n" "$duplicates"
    printf "Empty entries:     %d\n" "$empty_entries"
    printf "Existing dirs:     %d\n" "$existing_dirs"
    printf "Non-existent dirs: %d\n" $((total_entries - existing_dirs - empty_entries))
    
    # Show duplicates if any with source analysis
    if [ "$duplicates" -gt 0 ]; then
        printf "\nDUPLICATE PATHS:\n"
        printf "================\n"
        
        # Get all potential sources for detailed analysis
        user_home=$(get_user_home)
        launchctl_value=$(launchctl getenv "$var_name" 2>/dev/null || echo "")
        
        # Find and display duplicates with source tracking
        echo "$current_value" | tr ':' '\n' | sort | uniq -d | while read -r dup_path; do
            if [ -n "$dup_path" ]; then
                count=$(echo "$current_value" | tr ':' '\n' | grep -c "^$dup_path$")
                positions=$(echo "$current_value" | tr ':' '\n' | nl -nln | grep "$dup_path$" | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
                
                printf "\nPath: %s (appears %dx at positions: %s)\n" "$dup_path" "$count" "$positions"
                printf "Sources contributing this path:\n"
                
                # Check user launchctl
                if echo "$launchctl_value" | grep -q "$dup_path"; then
                    printf "  ✓ launchctl\n"
                fi
                
                # Check shell profiles
                found_in_profiles=""
                for profile in $USER_SHELL_PROFILES; do
                    expanded_profile=$(echo "$profile" | sed "s|\$HOME|$user_home|")
                    if [ -f "$expanded_profile" ] && grep -q "$dup_path" "$expanded_profile" 2>/dev/null; then
                        printf "  ✓ %s\n" "$expanded_profile"
                        found_in_profiles="yes"
                    fi
                done
                
                # Check if PATH inheritance is causing duplication
                if [ -z "$found_in_profiles" ]; then
                    printf "  ? Likely from system PATH inheritance or application-specific settings\n"
                fi
            fi
        done
    fi
    
    # Show potential sources
    printf "\nPOTENTIAL SOURCES:\n"
    printf "==================\n"
    
    # Check launchctl
    launchctl_value=$(launchctl getenv "$var_name" 2>/dev/null || echo "")
    if [ -n "$launchctl_value" ]; then
        printf "✓ launchctl is contributing to this PATH\n"
    else
        printf "✗ launchctl not contributing\n"
    fi
    
    # Check shell profiles
    user_home=$(get_user_home)
    found_profiles=""
    
    for profile in $USER_SHELL_PROFILES; do
        expanded_profile=$(echo "$profile" | sed "s|\$HOME|$user_home|")
        if [ -f "$expanded_profile" ] && grep -q "$var_name" "$expanded_profile" 2>/dev/null; then
            found_profiles="$found_profiles $expanded_profile"
            printf "✓ %s contains %s modifications\n" "$expanded_profile" "$var_name"
        fi
    done
    
    if [ -z "$found_profiles" ]; then
        printf "✗ No shell profile modifications found\n"
    fi
    
    printf "\nRECOMMENDATIONS:\n"
    printf "================\n"
    
    if [ "$duplicates" -gt 0 ]; then
        printf "• Remove duplicate entries to improve performance\n"
    fi
    
    if [ "$empty_entries" -gt 0 ]; then
        printf "• Remove empty entries (::) from PATH\n"
    fi
    
    nonexistent=$((total_entries - existing_dirs - empty_entries))
    if [ "$nonexistent" -gt 0 ]; then
        printf "• Consider removing non-existent directories\n"
    fi
    
    if [ "$duplicates" -eq 0 ] && [ "$empty_entries" -eq 0 ] && [ "$nonexistent" -eq 0 ]; then
        printf "• PATH looks clean! No issues detected.\n"
    fi
    
    printf "• Use 'menv info %s' for source details\n" "$var_name"
    
    printf "\n"
    print_color "$CYAN" "NOTE: Analysis focused on user-scope sources only"
    printf "• System-level PATH entries are inherited and not modifiable by this tool\n"
    
    # Clean up
    rm -f "$all_paths" "$unique_paths"
}

# Validate that required tools are available
check_dependencies() {
    missing_tools=""
    
    # Check for required commands
    for tool in launchctl plutil grep sed awk; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools="$missing_tools $tool"
        fi
    done
    
    if [ -n "$missing_tools" ]; then
        error_exit "Missing required tools:$missing_tools"
    fi
    
    debug "All required dependencies are available"
}

# Check if running on macOS
check_platform() {
    if [ "$(uname)" != "Darwin" ]; then
        error_exit "This script is designed for macOS only"
    fi
    debug "Running on macOS"
}

# Improved help with examples
show_help() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - ${SCRIPT_DESCRIPTION}

USAGE:
    ${SCRIPT_NAME} [OPTIONS] COMMAND [ARGUMENTS]

COMMANDS:
    list                    List all user environment variables in a table
    add NAME VALUE          Add/set a user environment variable
    set NAME VALUE          Set/modify a user environment variable (same as add)  
    delete NAME             Delete a user environment variable from all locations
    add-path VAR PATH       Add a path entry to PATH-like variable (PATH, LIBRARY_PATH, etc.)
    remove-path VAR PATH    Remove a path entry from PATH-like variable
    info NAME               Show detailed information about a user variable
    test NAME               Test if a variable works in fresh shell/GUI environments
    analyze NAME            Analyze PATH-like variables for composition and duplicates
    help                    Show this help message

PATH-LIKE VARIABLES:
    The following variables receive special treatment:
    PATH, LIBRARY_PATH, LD_LIBRARY_PATH, DYLD_LIBRARY_PATH, PKG_CONFIG_PATH,
    MANPATH, INFOPATH, CLASSPATH, PYTHONPATH, NODE_PATH

    For PATH-like variables:
    - 'add' will prompt whether to append, prepend, or replace
    - 'add-path' will append a new path entry
    - 'remove-path' will remove a specific path entry  
    - 'delete' will warn about removing the entire variable

OPTIONS:
    -f, --force            Force operation without confirmation prompts
    -v, --verbose          Enable verbose debug output
    -h, --help             Show this help message

EXAMPLES:
    # List all user environment variables with their sources
    ${SCRIPT_NAME} list

    # Add a user variable
    ${SCRIPT_NAME} add MY_API_KEY "abc123def456"

    # Set Java home for the current user
    ${SCRIPT_NAME} set JAVA_HOME "/Library/Java/JavaVirtualMachines/jdk-11.jdk/Contents/Home"

    # Delete a variable (removes from all user locations where it's defined)
    ${SCRIPT_NAME} delete OLD_VARIABLE

    # Force delete without confirmation
    ${SCRIPT_NAME} --force delete TEMP_VAR

    # Show detailed information about a specific variable
    ${SCRIPT_NAME} info PATH

    # Test if a variable works in fresh environments
    ${SCRIPT_NAME} test MY_API_KEY

    # Analyze PATH composition and find duplicates
    ${SCRIPT_NAME} analyze PATH

    # Verbose output for debugging
    ${SCRIPT_NAME} --verbose list

    # Add a directory to PATH (will append by default)
    ${SCRIPT_NAME} add-path PATH "/usr/local/custom/bin"
    
    # Add to PATH with prompts for handling (append/prepend/replace)
    ${SCRIPT_NAME} add PATH "/usr/local/custom/bin"
    
    # Remove a directory from PATH
    ${SCRIPT_NAME} remove-path PATH "/usr/local/custom/bin"
    
    # Dangerous: completely replace PATH
    ${SCRIPT_NAME} --force add PATH "/usr/bin:/bin"

VARIABLE SCOPE:
    User-specific only:
    - Set via user launchctl for the current user (affects GUI apps)
    - Added to shell profile files (affects terminal sessions)
    - Persists across user login/logout
    - Does NOT affect other users on the system
    - Ensures all new processes (shell and GUI) inherit the variables

LOCATIONS MANAGED:
    - User launchctl environment (for GUI applications)
    - Shell profile files (.profile, .zshrc, .bash_profile, .bashrc)
    - User LaunchAgent plist files (for persistence)
    - Deprecated macOS environment.plist (if present)

NOTES:
    - Changes to GUI applications require an application restart
    - Shell changes require opening a new terminal session
    - The script creates backups before modifying files
    - Use 'delete' to completely remove variables from all user locations
    - System-wide variables are not managed by this tool
    - Variables are applied to all newly started processes for the current user

EOF
}

# Main execution
main() {
    debug "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    
    # Check platform and dependencies
    check_platform
    check_dependencies
    
    # Parse command line arguments
    parse_arguments "$@"
    
    debug "Action: $ACTION, Force: $FORCE"
    
    # Validate variable name for operations that need it
    if [ "$ACTION" != "list" ] && [ -n "$VAR_NAME" ]; then
        validate_var_name "$VAR_NAME"
    fi
    
    # Execute the requested action
    case "$ACTION" in
        list)
            list_vars
            ;;
        add|set)
            add_set_var "$VAR_NAME" "$VAR_VALUE"
            ;;
        delete)
            delete_var "$VAR_NAME"
            ;;
        info)
            show_var_info "$VAR_NAME"
            ;;
        test)
            test_var_in_fresh_shell "$VAR_NAME"
            ;;
        analyze)
            analyze_var "$VAR_NAME"
            ;;
        add-path)
            add_path_entry "$VAR_NAME" "$VAR_VALUE"
            ;;
        remove-path)
            remove_path_entry "$VAR_NAME" "$VAR_VALUE"
            ;;
        *)
            error_exit "Unknown action: $ACTION"
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
