/**
 * rust_ftp.h
 *
 * C header file for Rust FTP static library FFI interface
 *
 * This header declares the C-compatible functions exported by the Rust
 * FTP library (librust_ftp.a) for use from Swift code.
 */

#ifndef RUST_FTP_H
#define RUST_FTP_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Initialize the Rust FTP library
 * Should be called once at application startup
 *
 * @return 0 on success, non-zero on error
 */
int32_t rust_ftp_init(void);

/**
 * Start an FTP monitoring session
 *
 * Spawns a background thread that monitors the specified FTP server
 * and downloads files according to the configuration.
 *
 * @param config_path Path to JSON configuration file
 * @param status_path Path where status updates will be written (JSON)
 * @param result_path Path where final result will be written (JSON)
 * @param session_path Path where session summary will be written (JSON)
 * @param hash_path Path for file hash tracking
 * @param session_id Unique identifier for this session
 * @return 0 on success, negative value on error:
 *         -1: config_path is null
 *         -2: config_path encoding error
 *         -3: status_path is null
 *         -4: status_path encoding error
 *         -5: result_path is null
 *         -6: result_path encoding error
 *         -7: session_path is null
 *         -8: session_path encoding error
 *         -9: hash_path is null
 *         -10: hash_path encoding error
 *         -11: session_id is null
 *         -12: session_id encoding error
 */
int32_t rust_ftp_start(
    const char *config_path,
    const char *status_path,
    const char *result_path,
    const char *session_path,
    const char *hash_path,
    const char *session_id
);

/**
 * Stop an FTP monitoring session
 *
 * Signals the session to shut down gracefully and waits for it to complete.
 *
 * @param session_id Unique identifier for the session to stop
 * @return 0 on success, negative value on error:
 *         -1: session_id is null
 *         -2: session_id encoding error
 *         -3: session not found
 */
int32_t rust_ftp_stop(const char *session_id);

/**
 * Get current status for a session
 *
 * Reads the status file for the session and returns its contents as a JSON string.
 * The returned string must be freed using rust_ftp_free_string().
 *
 * @param status_path Path to the status file to read
 * @return JSON string with status information, or NULL on error
 *         Caller must free the returned string with rust_ftp_free_string()
 */
char *rust_ftp_get_status(const char *status_path);

/**
 * Free a string allocated by Rust
 *
 * Must be called on strings returned by rust_ftp_get_status() to avoid memory leaks.
 *
 * @param s String to free (can be NULL)
 */
void rust_ftp_free_string(char *s);

/**
 * Shutdown the Rust FTP library
 *
 * Stops all running sessions and cleans up resources.
 * Should be called at application shutdown.
 *
 * @return 0 on success
 */
int32_t rust_ftp_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif /* RUST_FTP_H */
