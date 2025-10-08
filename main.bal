import ballerina/http;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;
import ballerina/sql;
import ballerina/crypto;
import ballerina/lang.array as array;
//import ballerina/io;

public type SecurePerson record {|
    int id?;
    string? persnr;
    string? krypterat_persnr;
    string? fornamn;
    string? krypterat_fornamn;
    string? efternamn;
    string? krypterat_efternamn;
    string? secret_key;
    string? skapad;
    string? uppdaterad;
|};

public type SecurePersonKrypteradeFalt record {|
    int id?;
    string? krypterat_persnr;
    string? krypterat_fornamn;
    string? krypterat_efternamn;
    string? skapad;
    string? uppdaterad;
|};

public type SecurePersonDekrypteradeFalt record {|
    int id?;
    string? dekrypterat_persnr;
    string? dekrypterat_fornamn;
    string? dekrypterat_efternamn;
    string? secret_key;
    string? skapad;
    string? uppdaterad;
|};

// Endast för intern felhantering
type EncryptAndDecryptResult record {|
    boolean success;
    string? encryptedValue;
    string? decryptedValue;
    string? errorMessage;
|};

// Databaskoppling
configurable string USER = ?;
configurable string PASSWORD = ?;
configurable string HOST = ?;
configurable int PORT = ?;
configurable string DATABASE = ?;

final postgresql:Client dbClient = check new postgresql:Client(
    host = HOST,
    username = USER,
    password = PASSWORD,
    port = PORT,
    database = DATABASE,
    options = {
        ssl: {
            mode: postgresql:REQUIRE
        }
    }
);


service /secure_person on new http:Listener(8081) {
    resource function post skapaKrypteradPerson(SecurePerson secureperson) returns json|error {
        
        string? encryptPersnr = null;
        string? encryptFornamn = null;
        string? encryptEfternamn = null;

        //--- Kryptera fält efter fält
        if secureperson.persnr != () && secureperson.persnr != "" && secureperson.persnr != "{?}" {
            EncryptAndDecryptResult krypteratPersnr = encryptTextAsJson(secureperson.persnr.toString(), secureperson.secret_key.toString());
            if !krypteratPersnr.success {
                return {
                    success: krypteratPersnr.success,
                    column: "persnr=" + secureperson.persnr.toString(),
                    encryptedValue: krypteratPersnr.encryptedValue,
                    decryptedValue: krypteratPersnr.decryptedValue,
                    errorMessage: krypteratPersnr.errorMessage
                };
            }
            encryptPersnr = krypteratPersnr.encryptedValue.toString();
        }
        
        if secureperson.fornamn != () && secureperson.fornamn != "" && secureperson.fornamn != "{?}" {
            EncryptAndDecryptResult krypteratFornamn = encryptTextAsJson(secureperson.fornamn.toString(), secureperson.secret_key.toString());
            if !krypteratFornamn.success {
                return {
                    success: krypteratFornamn.success,
                    column: "fornamn=" + secureperson.fornamn.toString(),
                    encryptedValue: krypteratFornamn.encryptedValue,
                    decryptedValue: krypteratFornamn.decryptedValue,
                    errorMessage: krypteratFornamn.errorMessage
                };
            }
            encryptFornamn = krypteratFornamn.encryptedValue.toString();
        }

        if secureperson.efternamn != () && secureperson.efternamn != "" && secureperson.efternamn != "{?}" {
            EncryptAndDecryptResult krypteratEfternamn = encryptTextAsJson(secureperson.efternamn.toString(), secureperson.secret_key.toString());
            if !krypteratEfternamn.success {
                return {
                    success: krypteratEfternamn.success,
                    column: "efternamn=" + secureperson.efternamn.toString(),
                    encryptedValue: krypteratEfternamn.encryptedValue,
                    decryptedValue: krypteratEfternamn.decryptedValue,
                    errorMessage: krypteratEfternamn.errorMessage
                };
            }
            encryptEfternamn = krypteratEfternamn.encryptedValue.toString();
        }

        sql:ParameterizedQuery query = `INSERT INTO secure_person (
                persnr,
                krypterat_persnr,
                fornamn,
                krypterat_fornamn,
                efternamn,
                krypterat_efternamn,
                secret_key
            ) VALUES (
                ${secureperson.persnr},
                ${encryptPersnr.toString()},
                ${secureperson.fornamn},
                ${encryptFornamn.toString()},
                ${secureperson.efternamn},
                ${encryptEfternamn.toString()},
                ${secureperson.secret_key}
            ) RETURNING id`;


        int insertedId = check dbClient->queryRow(query, int);
        if insertedId > 0 {
            return {
                message: "Krypterad Person skapades!",
                id: insertedId
            };
        } else {
            return {
                message: "Kunde inte skapa ny krypterad person!"
            };
        }
    }

    //   Hämta (GET) alla personer
    resource function get hamtaAllaPersoner() returns json {
        
        sql:ParameterizedQuery query = `SELECT * FROM secure_person order by id asc`;
        stream<SecurePerson, error?> resultStream = dbClient->query(query);
        SecurePerson[] resultList = [];
        error? e = resultStream.forEach(function(SecurePerson row) {
            resultList.push(row);
        });

        if e is error {
            return {
                "message": "Kunde inte hämta personer: " + e.message()
            };
        }
        return <json>resultList;
    }

    //   Hämta (GET) alla krypterade värden för personer
    resource function get hamtaAllaKrypteradeFaltForPersonerKrypterat() returns json {
        
        sql:ParameterizedQuery query = `SELECT 
            id, 
            krypterat_persnr, 
            krypterat_fornamn, 
            krypterat_efternamn, 
            skapad, 
            uppdaterad	
        FROM secure_person order by id asc`;

        stream<SecurePersonKrypteradeFalt, error?> resultStream = dbClient->query(query);
        SecurePersonKrypteradeFalt[] resultList = [];
        error? e = resultStream.forEach(function(SecurePersonKrypteradeFalt row) {
            resultList.push(row);
        });

        if e is error {
            return {
                "message": "Kunde inte hämta krypterade fält för personer: " + e.message()
            };
        }
        return <json>resultList;
    }

    //   Hämta (GET) alla krypterade värden för personer och dekryptera dem med nyckel
    resource function get hamtaAllaKrypteradeFaltForPersonerDekrypterat(string secretKey) returns json {
        
         // --- Säkerställ att nyckeln är 16 bytes (AES-128) ---
        if secretKey.length() != 16 {
            return {
                success: false,
                errorMessage: "secretKey måste vara 16 tkn lång!"
            };
        }
    
        sql:ParameterizedQuery query = `SELECT 
            id, 
            krypterat_persnr as dekrypterat_persnr, 
            krypterat_fornamn as dekrypterat_fornamn, 
            krypterat_efternamn as dekrypterat_efternamn,
            secret_key, 
            skapad, 
            uppdaterad	
        FROM secure_person order by id asc`;

        stream<SecurePersonDekrypteradeFalt, error?> resultStream = dbClient->query(query);
        SecurePersonDekrypteradeFalt[] resultList = [];
        error? e = resultStream.forEach(function(SecurePersonDekrypteradeFalt row) {

            if row.dekrypterat_persnr != () && row.dekrypterat_persnr != "" {
                EncryptAndDecryptResult dekrypteratPersnr = decryptTextAsJson(row.dekrypterat_persnr.toString(), secretKey.toString());
                row.dekrypterat_persnr = dekrypteratPersnr.decryptedValue;
            }
            if row.dekrypterat_fornamn != () && row.dekrypterat_fornamn != "" {
                EncryptAndDecryptResult dekrypteratFornamn = decryptTextAsJson(row.dekrypterat_fornamn.toString(), secretKey.toString());
                row.dekrypterat_fornamn = dekrypteratFornamn.decryptedValue;
            }
            if row.dekrypterat_efternamn != () && row.dekrypterat_efternamn != "" {
                EncryptAndDecryptResult dekrypteratEfternamn = decryptTextAsJson(row.dekrypterat_efternamn.toString(), secretKey.toString());
                row.dekrypterat_efternamn = dekrypteratEfternamn.decryptedValue;
            }
            resultList.push(row);
        });

        if e is error {
            return {
                "message": "Kunde inte hämta krypterade fält för personer: " + e.message()
            };
        }
        return <json>resultList;
    }

    // Kryptera ett värde med secret key
    resource function get krypteraEttInputVarde(string normaltVarde, string secretKey) returns json {
        return encryptTextAsJson(normaltVarde, secretKey);
    }

    // Dekryptera ett värde tillbaka till sitt ursprung med secret key
    resource function get dekrypteraEttInputVarde(string krypteratVarde, string secretKey) returns json {
        return decryptTextAsJson(krypteratVarde, secretKey);
    }
}

// Krypterar en text och returnerar alltid ett JSON-objekt
function encryptTextAsJson(string normaltVarde, string secretKey) returns EncryptAndDecryptResult {

    // --- Säkerställ att nyckeln är 16 bytes (AES-128) ---
    if secretKey.length() != 16 {
        return {
            success: false,
            encryptedValue: null,
            decryptedValue: null,
            errorMessage: "secretKey måste vara 16 tkn lång!"
        };
    }
    
    var encryptedResult = encryptText(normaltVarde, secretKey);
    if (encryptedResult is string) {
        return {
            success: true,
            encryptedValue: encryptedResult,
            decryptedValue: "N/A",
            errorMessage: null
        };
    } else {
        return {
            success: false,
            encryptedValue: null,
            decryptedValue: null,
            errorMessage: encryptedResult.message()
        };
    }
}

// Dekrypterar en base64-kodad text och returnerar alltid ett JSON-objekt
function decryptTextAsJson(string krypteratVarde, string secretKey) returns EncryptAndDecryptResult {
     // --- Säkerställ att nyckeln är 16 bytes (AES-128) ---
    if secretKey.length() != 16 {
        return {
            success: false,
            encryptedValue: null,
            decryptedValue: null,
            errorMessage: "secretKey måste vara 16 tkn lång!"
        };
    }

    var decryptedResult = decryptText(krypteratVarde, secretKey);
    if (decryptedResult is string) {
        return {
            success: true,
            encryptedValue: "N/A",
            decryptedValue: decryptedResult,
            errorMessage: null
        };
    } else {
        return {
            success: false,
            encryptedValue: null,
            decryptedValue: null,
            errorMessage: decryptedResult.message()
        };
    }
}

// Gör kryperingen. Returnera OK = string eller EJ OK = error
function encryptText(string normaltVarde, string secretKey) returns string|error {
    // Parsa input parametrar till byte
    byte[] data = normaltVarde.toBytes();
    byte[] pkcs5 = secretKey.toBytes();
    
    // Kryptera med AES-ECB + 16bit nyckel
    byte[] encrypted = check crypto:encryptAesEcb(data, pkcs5);
    
    // Returnera som base64 för att kunna sparas
    return encrypted.toBase64();
}

// Gör själva dekrypteringen – kan returnera string|error
function decryptText(string krypteratVarde, string secretKey) returns string|error {
    // Parsa input parameter från base64 till byte
    byte[] dataBytes = check array:fromBase64(krypteratVarde);
    // Parsa nyckel till byte
    byte[] pkcs5 = secretKey.toBytes();

    // Dekryptera med AES-ECB + 16bit nyckel
    byte[] decrypted = check crypto:decryptAesEcb(dataBytes, pkcs5);

    // Konvertera bytes -> string (UTF-8)
    string normaltVarde = check string:fromBytes(decrypted);

    // Returnera tillbaka som ursprungsvärde för att visas
    return normaltVarde;
}

