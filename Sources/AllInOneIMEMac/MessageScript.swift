import Foundation

/// The AppleScript that sends an iMessage (an SMS when there is no iMessage account). The handle and
/// the text are passed as arguments (`on run argv`), never written into the script, so nothing in
/// them can be read as AppleScript.
public enum MessageScript {
    public static let iMessage = """
        on run argv
        	set theHandle to item 1 of argv
        	set theText to item 2 of argv
        	tell application "Messages"
        		try
        			set theAccount to 1st account whose service type = iMessage
        		on error
        			set theAccount to 1st account whose service type = SMS
        		end try
        		send theText to participant theHandle of theAccount
        	end tell
        end run

        """

    /// osascript's arguments: the script comes on standard input ("-"), then its own arguments.
    public static func osascriptArguments(handle: String, text: String) -> [String] {
        ["-", handle, text]
    }
}
