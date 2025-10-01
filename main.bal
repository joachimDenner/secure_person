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
        sql:ParameterizedQuery query = `INSERT INTO secure_person (
                persnr,
                krypterat_persnr,
                secret_key
            ) VALUES (
                ${secureperson.persnr},
                ${secureperson.krypterat_persnr},
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

    //   Hämta (GET) alla krypterade personer utan secret key
    resource function get hamtaAllaKrypteradePersonerUtanNyckel() returns json {
        
        sql:ParameterizedQuery query = `SELECT * FROM secure_person order by id asc`;
        stream<SecurePerson, error?> resultStream = dbClient->query(query);
        SecurePerson[] resultList = [];
        error? e = resultStream.forEach(function(SecurePerson row) {
            resultList.push(row);
        });

        if e is error {
            return {
                "message": "Kunde inte hämta krypterade personer: " + e.message()
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
function encryptTextAsJson(string normaltVarde, string secretKey) returns json {

    // --- Säkerställ att nyckeln är 16 bytes (AES-128) ---
    if secretKey.length() != 16 {
        return {
            success: false,
            encryptedValue: null,
            errorMessage: "secretKey måste vara 16 tkn lång!"
        };
    }
    
    var encryptedResult = encryptText(normaltVarde, secretKey);
    if (encryptedResult is string) {
        return {
            success: true,
            encryptedValue: encryptedResult,
            errorMessage: null
        };
    } else {
        return {
            success: false,
            encryptedValue: null,
            errorMessage: encryptedResult.message()
        };
    }
}

// Dekrypterar en base64-kodad text och returnerar alltid ett JSON-objekt
function decryptTextAsJson(string krypteratVarde, string secretKey) returns json {
    var decryptedResult = decryptText(krypteratVarde, secretKey);
    if (decryptedResult is string) {
        return {
            success: true,
            decryptedValue: decryptedResult,
            errorMessage: null
        };
    } else {
        return {
            success: false,
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

