import ballerina/http;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;
import ballerina/sql;
import ballerina/log;
import ballerina/os;
import ballerina/uuid;

type person record {|
    int id?;
    string? utdelningsadress1;
    string? postnr;
    string? postort;
    string? fornamn;
    string? efternamn;
    string? typavidbet;
    string? idbet;
    string? skapaddatum;
    string? uppdateraddatum;
    string? lastevent;
    string? motpart;
    string? organisation;
    string? motpartid;
    string? land;
    string? merkontakt;
    string? telnr;
    string? mobilnr;
    string? epostadress;
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

// Steg 1 - SKV token variabler
configurable string SKV_TOKEN_URL = ?;
configurable string SKV_TOKEN_CLIENT_ID = ?;
configurable string SKV_TOKEN_CLIENT_SECRET = ?;
configurable string SKV_TOKEN_CERTFILE = ?;
configurable string SKV_TOKEN_KEYFILE = ?;

// Steg 2 - Skatteverket API - används i hämtning av persondata
configurable string SKV_API_URL = ?;
configurable string SKV_API_CLIENT_ID = ?;
configurable string SKV_API_CLIENT_SECRET = ?;

service /person on new http:Listener(8080) {
    
    resource function get hamtaTokenAndGUIDAndPerson(string personNr) returns json {
        string skvAccessToken = "";
        string skvCorrelationId = "";

        // 1A. Hämta access token
        json|error accessTokenRes = skvToken();
        if accessTokenRes is error {
            return {
                status: 500,
                message: "Misslyckades att hämta access token",
                detail: accessTokenRes.message()
            };
        }
        // 1B. Kontrollera att det är ett objekt (map)
        if accessTokenRes is map<json> {
            map<json> accessTokenMap = accessTokenRes;
            if accessTokenMap["access_token"] is string {
                skvAccessToken = <string>accessTokenMap["access_token"];
            } else {
                return {
                    status: 500,
                    message: "access_token saknas i svaret"
                };
            }
        } else {
            return {
                status: 500,
                message: "Felaktigt format på accessToken"
            };
        }

        // 2A. Hämta nytt GUID
        json|error newGuidRes = getNewGUID();
        if newGuidRes is error {
            return {
                status: 500,
                message: "Misslyckades att hämta GUID",
                detail: newGuidRes.message()
            };
        }

        // 2B. Kontrollera att det är ett objekt (map)
        if newGuidRes is map<json> {
            map<json> newGuidMap = newGuidRes;
            if newGuidMap["guid"] is string {
                skvCorrelationId = <string>newGuidMap["guid"];
            } else {
                return {
                    status: 500,
                    message: "GUID saknas i svaret"
                };
            }
        } else {
            return {
                status: 500,
                message: "Felaktigt format på newGuid"
            };
        }
        // Hämta persondata
        json|error personDataRes = hamtaPersonFranSKV(personNr, skvAccessToken, skvCorrelationId);
        if personDataRes is error {
            return {
                status: 500,
                message: "Misslyckades att hämta persondata",
                detail: personDataRes.message()
            };
        }

        json personData = <json>personDataRes;
        return {
            status: 200,
            guid: skvCorrelationId,
            token: skvAccessToken,
            person: personData
        };
    }


    // Vilken miljö kör vi i? Lokalt eller Kubernetes?
    resource function get checkEnv() returns json {
        string? choreoVar = os:getEnv("CHOREO_API_URL");
        string? k8sVar = os:getEnv("KUBERNETES_SERVICE_HOST");

        if choreoVar is string && choreoVar.trim() != "" {
            return {
                "environment": "Choreo",
                "variable": "CHOREO_API_URL",
                "value": choreoVar
            };
        } else if k8sVar is string && k8sVar.trim() != "" {
            return {
                "environment": "Kubernetes",
                "variable": "KUBERNETES_SERVICE_HOST",
                "value": k8sVar
            };
        } else {
            return {
                "environment": "Local",
                "variable": "N/A",
                "value": "N/A"
            };
        }
    }

    //   Hämta (GET) en person by id
    resource function get hamtaPerson(int id) returns json {
        sql:ParameterizedQuery query = `SELECT * FROM person WHERE id = ${id}`;
        stream<person, error?> resultStream = dbClient->query(query);

        person[] resultList = [];
        error? e = resultStream.forEach(function(person row) {
            resultList.push(row);
        });

        if e is error {
            return {
                "message": "Kunde inte hämta person: " + e.message()
            };
        }
        return <json>resultList;
    }

    // Skapa (POST) en ny person
    resource function post skapaPerson(person pers) returns json|error {
        sql:ParameterizedQuery query = `INSERT INTO person (
                utdelningsadress1,
                postnr,
                postort,
                fornamn,
                efternamn,
                typavidbet,
                idbet,
                skapaddatum,
                uppdateraddatum,
                lastevent,
                motpart,
                organisation,
                motpartid,
                land,
                merkontakt,
                telnr,
                mobilnr,
                epostadress
            ) VALUES (
                ${pers.utdelningsadress1},
                ${pers.postnr},
                ${pers.postort},
                ${pers.fornamn},
                ${pers.efternamn},
                ${pers.typavidbet},
                ${pers.idbet},
                ${pers.skapaddatum},
                ${pers.uppdateraddatum},
                ${pers.lastevent},
                ${pers.motpart},
                ${pers.organisation},
                ${pers.motpartid},
                ${pers.land},
                ${pers.merkontakt},
                ${pers.telnr},
                ${pers.mobilnr},
                ${pers.epostadress}
            ) RETURNING id`;

        int insertedId = check dbClient->queryRow(query, int);
        if insertedId > 0 {
            return {
                message: "Person skapades!",
                id: insertedId
            };
        } else {
            return {
                message: "Kunde inte skapa ny person!"
            };
        }
    }

    //   Hämta (GET) alla personer by id
    resource function get hamtaAllaPersonerSortByIdAsc() returns json {
        sql:ParameterizedQuery query = `SELECT * FROM person order by id asc`;
        stream<person, error?> resultStream = dbClient->query(query);

        person[] resultList = [];
        error? e = resultStream.forEach(function(person row) {
            resultList.push(row);
        });

        if e is error {
            return {
                "message": "Kunde inte hämta personer: " + e.message()
            };
        }
        return <json>resultList;
    }

    //   Hämta (GET) alla personer by efterNamn
    resource function get hamtaAllaPersonerSortByEfternamnAsc() returns json {
        sql:ParameterizedQuery query = `SELECT * FROM person ORDER BY efterNamn asc`;
        stream<person, error?> resultStream = dbClient->query(query);

        person[] resultList = [];
        error? e = resultStream.forEach(function(person row) {
            resultList.push(row);
        });

        if e is error {
            return {
                "message": "Kunde inte hämta personer: " + e.message()
            };
        }
        return <json>resultList;
    }

    // Uppdatera (PUT) en person
    resource function put uppdateraPerson(int id, person pers) returns json|error {
    sql:ParameterizedQuery query = `UPDATE person SET
        utdelningsadress1 = ${pers.utdelningsadress1},
        postnr = ${pers.postnr},
        postort = ${pers.postort},
        fornamn = ${pers.fornamn},
        efternamn = ${pers.efternamn},
        typavidbet = ${pers.typavidbet},
        idbet = ${pers.idbet},
        uppdateraddatum = ${pers.uppdateraddatum},
        lastevent = ${pers.lastevent},
        motpart = ${pers.motpart},
        organisation = ${pers.organisation},
        motpartid = ${pers.motpartid},
        land = ${pers.land},
        merkontakt = ${pers.merkontakt},
        telnr = ${pers.telnr},
        mobilnr = ${pers.mobilnr},
        epostadress = ${pers.epostadress}
        WHERE id = ${id}`;

        sql:ExecutionResult result = check dbClient->execute(query);
        int? affectedRowCount = result.affectedRowCount;

        if affectedRowCount is int && affectedRowCount > 0 {
            return {
                message: "Person uppdaterades!",
                id: id
            };
        } else {
            return {
                message: "Kunde inte uppdatera person!"
            };
        }
    }

    //  Ta bort (DELETE) en person
    resource function delete tabortPerson(int id) returns json {
        sql:ExecutionResult|error execResult = dbClient->execute(`
        DELETE FROM person WHERE id = ${id}
        `);

        if execResult is sql:ExecutionResult {
            int? affectedRowCount = execResult.affectedRowCount;
            if affectedRowCount is int && affectedRowCount == 0 {
                return { "message": "Person med id: " + id.toString() + " saknas!" };
            }
                        
            if affectedRowCount is int && affectedRowCount > 0 {
                return { "message": "Person med id: " + id.toString() + " borttagen!" };
            }
            
        } else {
            return { "message": "Fel inträffade vid borttagning: " + execResult.message() };
        }
    }

    //   Hämta (GET) en person mha idbet (personnummer)
    resource function get hamtaPersonByPersonnummer(string idBet) returns json {
        sql:ParameterizedQuery query = `SELECT * FROM person WHERE idbet = ${idBet}`;
        stream<person, error?> resultStream = dbClient->query(query);

        person[] resultList = [];
        error? e = resultStream.forEach(function(person row) {
            resultList.push(row);
        });

        if e is error {
            return {
                "message": "Kunde inte hämta person: " + e.message()
            };
        }
        return <json>resultList;
    }
}   

// Steg 1 - Hämta token från Skatteverket
function skvToken() returns json {
    // 1. Skapa request och sätt header
    // Motsvaras av -H "Content-Type: application/x-www-form-urlencoded" i cURL
    http:Request req = new;
    req.setHeader("Content-Type", "application/x-www-form-urlencoded");
     
    // 2. Förbered request-data NOT: Måste ligga på EN rad i denna kod även om den i cURL kan ligga på fler rader!!
    // Motsvaras av --data i cURL
    string formData = "grant_type=client_credentials"
        + "&client_id=" + SKV_TOKEN_CLIENT_ID
        + "&client_secret=" + SKV_TOKEN_CLIENT_SECRET;

    // 3. Lägg på formData på payload   
    req.setPayload(formData);

    // 4. Förbered debug-loggning om error
    // Hämta Content-Type-headern, eller fallback om den saknas
    string contentTypeHeader = "";
    string|http:HeaderNotFoundError h = req.getHeader("Content-Type");
    if h is string {
        contentTypeHeader = h;
    } else {
        contentTypeHeader = "Header saknas";
    }

    // 5. Bygg på debug-strängen
    string requestDebug = string `url=${SKV_TOKEN_URL}, headers=${contentTypeHeader}, payload=${formData}`;

    do {
        http:Client skvClient = check new(SKV_TOKEN_URL, {
            secureSocket: {
                key: {
                    certFile: SKV_TOKEN_CERTFILE,
                    keyFile: SKV_TOKEN_KEYFILE
                },
                protocol: { name: http:TLS, versions: ["TLSv1.2"] },
                ciphers: [
                    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
                    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
                ]
            }
        });

        // 6. Skicka POST-anrop
        http:Response tokenResp = check skvClient->post("", req);
        if tokenResp.statusCode == 200 {
            json|error tokenJson = tokenResp.getJsonPayload();
            if tokenJson is json {
                log:printInfo("Token hämtad");
                return tokenJson;
            } else {
                fail error("1) requestDebug: " + requestDebug);
            }
        } else {
            // Försök hämta respons som JSON
            json|error errorJson = tokenResp.getJsonPayload();
            if errorJson is json {
                fail error("Skatteverket svarade med status: " + tokenResp.statusCode.toString() + ", 2) requestDebug: " + requestDebug);
            } else {
                // Om inte JSON, hämta textpayload
                string|error errorText = tokenResp.getTextPayload();
                if errorText is string {
                    fail error("Skatteverket svarade med status: " + tokenResp.statusCode.toString()
                            + " och payload: " + errorText + ", 3) requestDebug: " + requestDebug);
                } else {
                    fail error("Skatteverket svarade med status: " + tokenResp.statusCode.toString()
                            + " men kunde inte läsa payload" + ", 4) requestDebug: " + requestDebug);
                }
            }
        }
    } on fail error e {
        return {
            "status": 500,
            "error": e.message(),
            "stackTrace": e.stackTrace().toString(),
            "request": requestDebug
        };
    }
}

// Steg 2 - Skapa en ny GUID. Att användas i SKV api
function getNewGUID() returns json {
    string guid = uuid:createType4AsString();
    return { "guid": guid };
}

// Steg 3 - Hämta (GET) en personpost ifrån SKV
// PersonNr: Ange ett personnummer som skall hämtas. I ett format som SKV's api vill ha det.
// skvAccessToken: Access-token som hämtats i steg 1.     
// skvCorrelationId: GUID som hämtats i steg 2.
    
function hamtaPersonFranSKV(string personNr, string skvAccessToken, string skvCorrelationId) returns json {
    do {
        // 1. Skapa request och sätt header
        http:Request req = new;

        // 2. Bygg header
        req.setHeader("Content-Type", "application/json");
        req.setHeader("Authorization", "Bearer " + skvAccessToken);
        req.setHeader("skv_client_correlation_id", skvCorrelationId);
        req.setHeader("client_id", SKV_API_CLIENT_ID);
        req.setHeader("client_secret", SKV_API_CLIENT_SECRET);

        // 3. Förbered payload NOT: Måste ligga på EN rad i denna kod även om den i cURL kan ligga på fler rader!!
        // Motsvaras av --data i cURL
        string formData = "{\"bestallning\":{\"organisationsnummer\":162021004748,\"bestallningsidentitet\":\"00000236-FO01-0001\"},\"sokvillkor\":[{\"identitetsbeteckning\":" + personNr + "}]}";

        // 5. Lägg på formData på payload
        req.setPayload(formData);

        http:Client skvClient = check new(SKV_API_URL);

        // 8. Skicka POST-anrop
        http:Response personResp = check skvClient->post("", req);

        if personResp.statusCode == 200 {
            json|error personJson = personResp.getJsonPayload();
            if personJson is json {
                log:printInfo("Person hämtad");
                return personJson;
            } else {
                fail error("1) requestDebug: N/A");
            }
        } else {
            // Försök hämta respons som JSON
            json|error errorJson = personResp.getJsonPayload();
            if errorJson is json {
                fail error("Skatteverket svarade med status: " + personResp.statusCode.toString() + ", 2) requestDebug: N/A");
            } else {
                // Om inte JSON, hämta textpayload
                string|error errorText = personResp.getTextPayload();
                if errorText is string {
                    fail error("Skatteverket svarade med status: " + personResp.statusCode.toString()
                            + " och payload: " + errorText + ", 3) requestDebug: N/A");
                } else {
                    fail error("Skatteverket svarade med status: " + personResp.statusCode.toString()
                            + " men kunde inte läsa payload" + ", 4) requestDebug: N/A");
                }
            }
        }
    } on fail error e {
        return {
            "status": 500,
            "error": e.message(),
            "stackTrace": e.stackTrace().toString(),
            "request": "N/A"
        };
    }
}
