// The official settings file is JavaScript. Keeping this small override in the
// recipe makes the editor require credentials while retaining Node-RED defaults.
module.exports = {
    uiPort: process.env.PORT || 1880,
    adminAuth: {
        type: "credentials",
        users: [{
            username: process.env.NODE_RED_ADMIN_USERNAME,
            password: process.env.NODE_RED_ADMIN_PASSWORD_HASH,
            permissions: "*"
        }]
    },
    credentialSecret: process.env.NODE_RED_CREDENTIAL_SECRET,
    flowFile: "flows.json",
    flowFilePretty: true
};
