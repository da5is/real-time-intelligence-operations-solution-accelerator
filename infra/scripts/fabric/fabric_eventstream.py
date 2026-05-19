#!/usr/bin/env python3
"""
Fabric Eventstream Creation Module

This module provides Eventstream creation functionality for Microsoft Fabric operations.
It creates the Eventstream with minimal configuration, and the detailed definition should be 
updated using fabric_eventstream_definition.py script.

Usage:
    python fabric_eventstream.py --workspace-id "workspace-id" --eventstream-name "My Eventstream"

Requirements:
    - fabric_api.py module in the same directory
    - Azure CLI authentication or other Azure credentials configured
    - Contributor permissions in the target workspace
"""

import argparse
import sys
import time
from fabric_api import FabricWorkspaceApiClient, FabricApiError
from fabric_auth import authenticate_workspace


def create_eventstream(workspace_client: FabricWorkspaceApiClient,
                      eventstream_name: str = "rti_eventstream"):
    """
    Create an Eventstream in the specified workspace if it doesn't exist.
    
    Args:
        workspace_client: Authenticated FabricWorkspaceApiClient instance
        eventstream_name: Name for the eventstream (required, whitespaces will be removed)

    Returns:
        Dictionary with eventstream information if successful
        
    Raises:
        Exception: If eventstream creation fails
    """
    try:
        # Validate and clean eventstream name (remove whitespaces)
        if not eventstream_name or not eventstream_name.strip():
            raise ValueError("eventstream_name is required and cannot be empty")
        
        eventstream_name = eventstream_name.strip().replace(" ", "")
        if not eventstream_name:
            raise ValueError("eventstream_name cannot be empty after removing whitespaces")
        
        # Use provided workspace client
        print("🔍 Using provided Fabric Workspace API client...")

        # Check if eventstream already exists
        print("🔍 Checking for existing eventstream...")
        existing_eventstream = workspace_client.get_eventstream_by_name(eventstream_name)
        
        if existing_eventstream:
            # Delete and recreate to ensure a clean state for definition updates
            existing_id = existing_eventstream.get('id')
            print(
                f"♻️  Eventstream '{eventstream_name}' already exists"
                f" (ID: {existing_id}), deleting to recreate..."
            )
            workspace_client.delete_eventstream(existing_id)
            print(f"✅ Deleted existing eventstream '{eventstream_name}'")

        # Create a new eventstream with minimal configuration
        print(f"📊 Creating new eventstream '{eventstream_name}'...")
        max_retries = 6
        retry_delay = 10  # seconds
        for attempt in range(1, max_retries + 1):
            try:
                eventstream_result = workspace_client.create_eventstream(
                    display_name=eventstream_name,
                    description=f"Eventstream: {eventstream_name}"
                )
                break
            except FabricApiError as create_err:
                is_name_conflict = (
                    getattr(create_err, 'status_code', None) == 409
                    or "NotAvailableYet" in str(create_err)
                )
                if is_name_conflict and attempt < max_retries:
                    print(
                        f"⏳ Name not available yet, retrying"
                        f" in {retry_delay}s... "
                        f"(attempt {attempt}/{max_retries})"
                    )
                    time.sleep(retry_delay)
                else:
                    raise
        
        eventstream_id = eventstream_result.get('id')
        print(f"✅ Successfully created eventstream '{eventstream_name}' (ID: {eventstream_id})")
        print(f"⚠️  Note: Use fabric_eventstream_definition.py to set up the eventstream configuration")
        
        return eventstream_result
        
    except FabricApiError as e:
        print(f"❌ FabricApiError ({e.status_code}): {e}")
        raise
    except Exception as e:
        print(f"❌ Error: {e}")
        raise

def main():
    """Main function to handle command line arguments and execute the eventstream creation."""
    parser = argparse.ArgumentParser(
        description="Create an Eventstream in a Fabric workspace",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic usage with required parameters:
  python fabric_eventstream.py --workspace-id "12345678-1234-1234-1234-123456789012" --eventstream-name "MyEventstream"
  
  Note: Eventstream names cannot contain whitespaces and will be automatically removed.
        Use fabric_eventstream_definition.py to configure the eventstream after creation.
        """
    )
    
    parser.add_argument(
        "--workspace-id", 
        required=True, 
        help="ID of the workspace where the eventstream will be created"
    )
    
    parser.add_argument(
        "--eventstream-name",
        default="rti_eventstream",
        help="Name for the eventstream (whitespaces will be automatically removed)"
    )
    
    # Parse arguments
    args = parser.parse_args()
    
    # Execute the main logic
    
    workspace_client = authenticate_workspace(args.workspace_id)
    if not workspace_client:
        print("❌ Failed to authenticate workspace-specific Fabric API client")
        sys.exit(1)
    
    result = create_eventstream(
        workspace_client=workspace_client,
        eventstream_name=args.eventstream_name
    )
    
    print(f"\n✅ Eventstream ID: {result.get('id')}")
    print(f"✅ Eventstream Name: {result.get('displayName')}")


if __name__ == "__main__":
    main()