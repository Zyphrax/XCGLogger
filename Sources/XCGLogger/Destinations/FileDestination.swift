//
//  FileDestination.swift
//  XCGLogger: https://github.com/DaveWoodCom/XCGLogger
//
//  Created by Dave Wood on 2014-06-06.
//  Copyright © 2014 Dave Wood, Cerebral Gardens.
//  Some rights reserved: https://github.com/DaveWoodCom/XCGLogger/blob/master/LICENSE.txt
//

// MARK: - FileDestination
/// A standard destination that outputs log details to a file
open class FileDestination: BaseDestination {
    // MARK: - Properties
    /// Logger that owns the destination object
    open override var owner: XCGLogger? {
        didSet {
            if owner != nil {
                openFile()
            }
            else {
                closeFile()
            }
        }
    }

    /// FileURL of the file to log to
    open var writeToFileURL: URL? = nil {
        didSet {
            openFile()
        }
    }

    /// File handle for the log file
    internal var logFileHandle: FileHandle? = nil

    /// Option: whether or not to append to the log file if it already exists
    internal var shouldAppend: Bool

    /// Option: if appending to the log file, the string to output at the start to mark where the append took place
    internal var appendMarker: String?

    // MARK: - Life Cycle
    public init(owner: XCGLogger? = nil, writeToFile: Any?, identifier: String = "", shouldAppend: Bool = false, appendMarker: String? = "-- ** ** ** --") {
        self.shouldAppend = shouldAppend
        self.appendMarker = appendMarker

        if writeToFile is NSString {
            writeToFileURL = URL(fileURLWithPath: writeToFile as! String)
        }
        else {
            writeToFileURL = writeToFile as? URL
        }

        super.init(owner: owner, identifier: identifier)

        if owner != nil {
            openFile()
        }
    }

    deinit {
        // close file stream if open
        closeFile()
    }

    // MARK: - File Handling Methods
    /// Open the log file for writing.
    ///
    /// - Parameters:   None
    ///
    /// - Returns:  Nothing
    ///
    private func openFile() {
        guard let owner = owner else { return }

        if logFileHandle != nil {
            closeFile()
        }

        if let writeToFileURL = writeToFileURL {

            let fileManager: FileManager = FileManager.default
            let fileExists: Bool = fileManager.fileExists(atPath: writeToFileURL.path)
            if !shouldAppend || !fileExists {
                fileManager.createFile(atPath: writeToFileURL.path, contents: nil, attributes: nil)
            }

            do {
                logFileHandle = try FileHandle(forWritingTo: writeToFileURL)
                if fileExists && shouldAppend {
                    logFileHandle?.seekToEndOfFile()

                    if let appendMarker = appendMarker,
                        let encodedData = "\(appendMarker)\n".data(using: String.Encoding.utf8) {

                        _try({
                            self.logFileHandle?.write(encodedData)
                        },
                        catch: { (exception: NSException) in
                            owner._logln("Objective-C Exception occurred: \(exception)", level: .error)
                        })
                    }
                }
            }
            catch let error as NSError {
                owner._logln("Attempt to open log file for \(fileExists && shouldAppend ? "appending" : "writing") failed: \(error.localizedDescription)", level: .error)
                logFileHandle = nil
                return
            }

            owner.logAppDetails(selectedDestination: self)

            let logDetails = LogDetails(level: .info, date: Date(), message: "XCGLogger " + (fileExists && shouldAppend ? "appending" : "writing") + " log to: " + writeToFileURL.absoluteString, functionName: "", fileName: "", lineNumber: 0, userInfo: XCGLogger.Constants.internalUserInfo)
            owner._logln(logDetails.message, level: logDetails.level)
            if owner.destination(withIdentifier: identifier) == nil {
                processInternal(logDetails: logDetails)
            }
        }
    }

    /// Close the log file.
    ///
    /// - Parameters:   None
    ///
    /// - Returns:  Nothing
    ///
    private func closeFile() {
        logFileHandle?.closeFile()
        logFileHandle = nil
    }

    /// Suspend logging temporarily and execute the provided closure.
    /// You can use this method to perform operations on the log file without it being locked.
    ///
    /// A log queue is required otherwise log messages might slip passed us.
    ///
    /// - Parameters:
    ///     - closure:    The code to execute while the file is accessible.
    ///
    /// - Returns:  Nothing
    ///
    open func executeWhileSuspended(_ closure: @escaping () -> Void) {
        precondition(logQueue != nil, "LogQueue should be set")

        logQueue?.async { [weak logFileHandle] in
            logFileHandle?.synchronizeFile()
            closure()
        }
    }

    /// Rotate the log file, storing the existing log file in the specified location.
    ///
    /// - Parameters:
    ///     - archiveToFile:    FileURL or path (as String) to where the existing log file should be rotated to.
    ///
    /// - Returns:
    ///     - true:     Log file rotated successfully.
    ///     - false:    Error rotating the log file.
    ///
    @discardableResult open func rotateFile(to archiveToFile: Any) -> Bool {
        var archiveToFileURL: URL? = nil

        if archiveToFile is NSString {
            archiveToFileURL = URL(fileURLWithPath: archiveToFile as! String)
        }
        else if archiveToFile is URL {
            archiveToFileURL = archiveToFile as? URL
        }
        else {
            return false
        }

        if let archiveToFileURL = archiveToFileURL,
            let writeToFileURL = writeToFileURL {

            let fileManager: FileManager = FileManager.default
            guard !fileManager.fileExists(atPath: archiveToFileURL.path) else { return false }

            closeFile()
            haveLoggedAppDetails = false

            do {
                try fileManager.moveItem(atPath: writeToFileURL.path, toPath: archiveToFileURL.path)
            }
            catch let error as NSError {
                openFile()
                owner?._logln("Unable to rotate file \(writeToFileURL.path) to \(archiveToFileURL.path): \(error.localizedDescription)", level: .error)
                return false
            }

            owner?._logln("Rotated file \(writeToFileURL.path) to \(archiveToFileURL.path)", level: .info)
            openFile()
            return true
        }

        return false
    }

    // MARK: - Overridden Methods
    /// Write the log to the log file.
    ///
    /// - Parameters:
    ///     - message:   Formatted/processed message ready for output.
    ///
    /// - Returns:  Nothing
    ///
    open override func write(message: String) {
        if let encodedData = "\(message)\n".data(using: String.Encoding.utf8) {
            _try({
                self.logFileHandle?.write(encodedData)
            },
            catch: { (exception: NSException) in
                self.owner?._logln("Objective-C Exception occurred: \(exception)", level: .error)
            })
        }
    }
}
