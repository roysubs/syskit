#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02
import sqlite3
import datetime
import os   # Required for '~' in path

# --- Configuration ---
DB_PATH = '/home/boss/.config/heimdall-docker/www/app.sqlite'
DB_PATH = os.path.expanduser('~/.config/heimdall-docker/www/app.sqlite')   # Modified with import os

# --- New Item Details ---
new_item_title = "Another Programmatic Link" # Changed title to avoid collision
new_item_url = "http://another-example.com"
new_item_colour = "#2ecc71"  # A nice green
new_item_icon = "fas fa-cogs"  # Font Awesome cogs icon

# --- Fixed Values based on our findings ---
USER_ID = 1
ITEM_TYPE = 0 # 0 for regular app links
PINNED_STATUS = 1 # 1 to make it visible and pinned
HOME_DASHBOARD_TAG_ID = 0 # This is the 'tag_id' for "app.dashboard"

def get_next_order_value(cursor, user_id, tag_id):
    """
    Gets the maximum 'order' value for items under a specific tag_id for the user 
    and adds 1.
    This assumes 'order' is specific to items under the same tag on the dashboard.
    """
    # We need to join with item_tag to get items for a specific dashboard/tag
    cursor.execute('''
        SELECT MAX(i."order") 
        FROM items i
        JOIN item_tag it ON i.id = it.item_id
        WHERE i.user_id = ? AND it.tag_id = ? AND i.deleted_at IS NULL
    ''', (user_id, tag_id))
    max_order = cursor.fetchone()[0]
    if max_order is None: # No items yet for this tag
        return 0
    return max_order + 1

def add_new_heimdall_item_and_tag(title, url, colour, icon, db_path):
    conn = None
    new_item_id = None
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        # Get the next order value for the "Home dashboard"
        next_order = get_next_order_value(cursor, USER_ID, HOME_DASHBOARD_TAG_ID)

        # 1. Insert into 'items' table
        sql_insert_item = """
            INSERT INTO items (
                title, colour, icon, url, description,
                pinned, "order", deleted_at, created_at, updated_at,
                type, user_id, class, appid, appdescription
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        item_data = (
            title, colour, icon, url, None,  # description is None
            PINNED_STATUS, next_order, None, current_time, current_time, # deleted_at is None
            ITEM_TYPE, USER_ID, None, None, None # class, appid, appdescription are None for basic links
        )
        cursor.execute(sql_insert_item, item_data)
        new_item_id = cursor.lastrowid # Get the ID of the newly inserted item
        print(f"Successfully added item: '{title}' with ID: {new_item_id} and order: {next_order}")

        # 2. Insert into 'item_tag' table to link it to the "Home dashboard"
        if new_item_id is not None:
            sql_insert_item_tag = """
                INSERT INTO item_tag (item_id, tag_id, created_at, updated_at)
                VALUES (?, ?, ?, ?)
            """
            item_tag_data = (new_item_id, HOME_DASHBOARD_TAG_ID, current_time, current_time)
            cursor.execute(sql_insert_item_tag, item_tag_data)
            print(f"Successfully tagged item ID: {new_item_id} with tag_id: {HOME_DASHBOARD_TAG_ID}")

        conn.commit()
        return new_item_id

    except sqlite3.Error as e:
        print(f"SQLite error: {e}")
        if conn:
            conn.rollback()
        return None
    finally:
        if conn:
            conn.close()

if __name__ == '__main__':
    added_id = add_new_heimdall_item_and_tag(
        new_item_title, new_item_url, new_item_colour, new_item_icon, DB_PATH
    )
    
    if added_id:
        print(f"\nVerifying: Check your Heimdall dashboard for '{new_item_title}'.")
        print("It should now appear directly on the main dashboard.")
        print("You might need to refresh the Heimdall page in your browser.")
