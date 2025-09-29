import ballerina/http;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;
import ballerina/sql;
//import ballerina/log;
//import ballerina/os;
//import ballerina/uuid;
import ballerina/crypto;

type person record {|
    int id?;
    string? persnr_hmac_value;
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
    // Skapa (POST) en ny krypterad person
    resource function post skapaKrypteradPerson(string persnr, string secretKey) returns json|error {
        
        // Skapa HMAC med SHA-256
        byte[] hmacBytes = check crypto:hmacSha256(persnr.toBytes(), secretKey.toBytes());
        string hmacHex   = hmacBytes.toBase16();
        
        sql:ParameterizedQuery query = `INSERT INTO secure_person (
                persnr_hmac_value
            ) VALUES (
                ${hmacHex}
            ) RETURNING id`;

        int insertedId = check dbClient->queryRow(query, int);
        if insertedId > 0 {
            return {
                message: "Person skapades krypterat!",
                id: insertedId
            };
        } else {
            return {
                message: "Kunde inte skapa ny person krypterat!"
            };
        }
    }

    //   Hämta (GET) alla krypterade personer utan secret key
    resource function get hamtaAllaKrypteradePersonerUtanNyckel() returns json {
        
        sql:ParameterizedQuery query = `SELECT * FROM secure_person order by id asc`;
        stream<person, error?> resultStream = dbClient->query(query);

        person[] resultList = [];
        error? e = resultStream.forEach(function(person row) {
            resultList.push(row);
        });

        if e is error {
            return {
                "message": "Kunde inte hämta krypterade personer: " + e.message()
            };
        }
        return <json>resultList;
    }
}
