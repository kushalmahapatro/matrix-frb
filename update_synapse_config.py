#!/usr/bin/env python3
import yaml
import sys

# Read the current configuration
with open('/data/homeserver.yaml', 'r') as f:
    config = yaml.safe_load(f)

# Enable registration
config['enable_registration'] = True
config['enable_registration_without_verification'] = True

# Write the updated configuration
with open('/data/homeserver.yaml', 'w') as f:
    yaml.dump(config, f, default_flow_style=False)

print("Registration enabled in homeserver.yaml") 