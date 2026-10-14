#include <libsecret/secret.h>
#include <stdlib.h>

static const SecretSchema swift_openui_keychain_schema = {
    "com.swiftopenui.security.generic-password", SECRET_SCHEMA_NONE,
    {
        { "service", SECRET_SCHEMA_ATTRIBUTE_STRING },
        { "account", SECRET_SCHEMA_ATTRIBUTE_STRING },
        { "access-group", SECRET_SCHEMA_ATTRIBUTE_STRING },
        { NULL, 0 }
    }
};

static inline gboolean swift_openui_secret_store(
    const char *service, const char *account, const char *access_group,
    const char *label, const char *password, GError **error
) {
    return secret_password_store_sync(
        &swift_openui_keychain_schema, SECRET_COLLECTION_DEFAULT, label, password,
        NULL, error, "service", service, "account", account,
        "access-group", access_group, NULL
    );
}

static inline char *swift_openui_secret_lookup(
    const char *service, const char *account, const char *access_group, GError **error
) {
    return secret_password_lookup_sync(
        &swift_openui_keychain_schema, NULL, error, "service", service,
        "account", account, "access-group", access_group, NULL
    );
}

static inline gboolean swift_openui_secret_clear(
    const char *service, const char *account, const char *access_group, GError **error
) {
    return secret_password_clear_sync(
        &swift_openui_keychain_schema, NULL, error, "service", service,
        "account", account, "access-group", access_group, NULL
    );
}
