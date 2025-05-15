/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

// import {onRequest} from "firebase-functions/v2/https";
// import * as logger from "firebase-functions/logger";

// Start writing functions
// https://firebase.google.com/docs/functions/typescript

// export const helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
// import fetch from "node-fetch";
// import {user} from "firebase-functions/v1/auth";
import {GeoPoint} from "firebase-admin/firestore";

admin.initializeApp();
const db = admin.firestore();

// Define the expected data structures
interface EarthquakeFeature {
    id: string;
    properties: {
        place: string;
        mag: number;
        time: number;
    };
    geometry: {
        coordinates: [number, number]; // [longitude, latitude]
    };
}

interface EarthquakeData {
    features: EarthquakeFeature[];
}

export const fetchAndStoreEarthquakes = functions.pubsub
  .schedule("every 15 minutes")
  .onRun(async (_context) => {
    const fetch = (await import("node-fetch")).default;

    // Set the dates for the query
    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(today.getDate() - 1);

    const starttime = yesterday.toISOString();
    const endtime = today.toISOString();

    // USGS URL for fetching earthquake data
    const url = `https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=${encodeURIComponent(starttime)}&endtime=${encodeURIComponent(endtime)}&minlatitude=6.0&maxlatitude=37.6&minlongitude=68.0&maxlongitude=97.4&minmagnitude=4`;

    try {
      const response = await fetch(url);

      if (!response.ok) {
        throw new Error(`Error fetching data: ${response.statusText}`);
      }

      // Cast the fetched data to the defined type
      const data = await fetchWithRetries(url) as EarthquakeData;
      // const structuredData = parseEarthquakeData(data.features);
      // Step to parse data
      const newEarthquakes: EarthquakeFeature[] = [];
      const batch = db.batch();

      for (const feature of data.features) {
        const id = feature.id;
        // Check if this earthquake data already exists
        const docRef = db.collection("disasters").doc(id);
        const docSnapshot = await docRef.get();

        if (!docSnapshot.exists) {
          // Validate the structure of the earthquake data
          if (!feature.id ||
            !feature.properties ||
            !feature.geometry ||
            !feature.geometry.coordinates) {
            console.warn(`Invalid earthquake data: ${JSON.stringify(feature)}`);
            continue;
          }

          const quakeData = {
            type: "earthquake",
            description: feature.properties.place,
            location: new admin.firestore.GeoPoint(
              feature.geometry.coordinates[1],
              feature.geometry.coordinates[0]
            ),
            magnitude: feature.properties.mag,
            timestamp: admin.firestore.Timestamp.fromMillis(
              feature.properties.time
            ),
            updatedAt: admin.firestore.Timestamp.now(),
          };

          // Store the earthquake data using batch set
          batch.set(docRef, quakeData, {merge: true});
          newEarthquakes.push(feature); // Add to newEarthquakes array
        } else {
          console.log(`Earthquake with ID ${id} already exists. Skipping...`);
        }
      }

      await batch.commit();
      console.log("Earthquake data successfully updated in Firestore.");

      if (newEarthquakes.length > 0) {
        await fetchAndProcessAlerts(newEarthquakes);
        console.log("Alerts processed successfully.");
      }
    } catch (error) {
      console.error("Error fetching and storing earthquake data:", error);
    }
  });

export const addUser = functions.https.onRequest(async (req, res) => {
  // Implementing a function to add users
  try {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const {uid, alertsEnabled, token, location} = req.body;

    if (!uid || typeof alertsEnabled !== "boolean" ||
      !token || !location || !location.latitude || !location.longitude) {
      res.status(400).send("Bad Request: Missing required fields.");
      return;
    }

    const userRef = db.collection("users").doc(uid);
    await userRef.set({
      alertsEnabled,
      token,
      location: new admin.firestore.GeoPoint(
        location.latitude, location.longitude
      ),
    }, {merge: true});

    res.status(201).send("User added successfully.");
  } catch (error) {
    console.error("Error adding user:", error);
    res.status(500).send("Internal Server Error");
  }
});

export const userAlertTrigger = functions.https.onRequest(async (req, res) => {
  try {
    // Logic to fetch alerts from Firestore and handle notifications
    const significantEarthquakes = await db.collection("disasters")
      .where("magnitude", ">=", 4)
      .get();
    if (significantEarthquakes.empty) {
      res.status(200).send("No significant earthquakes found.");
      return;
    }
    const earthquakes: EarthquakeFeature[] =
      significantEarthquakes.docs.map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          properties: {
            place: data.place,
            mag: data.magnitude,
            time: data.timestamp.toMillis(),
          },
          geometry: {
            coordinates: [data.location.longitude, data.location.latitude],
          },
        };
      });
    await fetchAndProcessAlerts(earthquakes);
    res.status(200).send("Alerts processed successfully.");
    return;
  } catch (error) {
    console.error("Error processing alerts:", error);
    res.status(500).send("Internal Server Error");
    return;
  }
});

/**
* Fetches alerts from the server and processes them.
*
* This function retrieves alert data, processes the information,
* and handles it accordingly (e.g., storing in a database,
* sending notifications).
*
* @param {EarthquakeFeature[]} newEarthquakes -
* An array of new earthquake data to process.
* @return {Promise<void>}
* A promise that resolves when the processing of alerts is complete.
*/
async function fetchAndProcessAlerts(newEarthquakes: EarthquakeFeature[]) {
  const significantEarthquakes = newEarthquakes
    .filter((e) => e.properties.mag >= 4);
  if (significantEarthquakes.length === 0) return;
  const userQuery = await admin.firestore().collection("users").get();
  userQuery.forEach((userDoc) => {
    const userData = userDoc.data();
    // Assume user location is stored as GeoPoint
    const userLocation = userData?.location;
    const userToken = userData?.token;

    if (userLocation && userToken) {
      significantEarthquakes.forEach((earthquake) => {
        const quakeLocation = new GeoPoint(
          earthquake.geometry.coordinates[1],
          earthquake.geometry.coordinates[0]
        );
        const distance = calculateDistance(userLocation, quakeLocation);
        if (distance <= 10) { // 10 km range
          console.log(`Processing earthquake: ${earthquake.properties.place},
            magnitude: ${earthquake.properties.mag}`);
          console.log(`User ${userDoc.id} is within range.
            Sending notification...`);
          earthquakeNotification(userToken, earthquake, userDoc);
        }
      });
    }
  });
}

//   const earthquakeQuery = await admin.firestore().collection("disasters")
//     .where("magnitude", ">=", 4)
//     .get();

//   if (!earthquakeQuery.empty) {
//     const earthquakes = earthquakeQuery.docs.map((doc) =>
//       doc.data() as { magnitude: number; place: string });
//     const userQuery = await admin.firestore().collection("users").get();
//     userQuery.forEach((userDoc) => {
//       const userData = userDoc.data();

//       // Send alerts to users based on their preference
//       if (userData.alertsEnabled) {
//         earthquakeNotification(userData, earthquakes);
//       }
//     });
//   }
// }

/**
 * Calculates the distance between two geographical
 * points using the Haversine formula.
 *
 * @param {GeoPoint} point1 - The first geographical point.
 * @param {GeoPoint} point2 - The second geographical point.
 * @returns {number} The distance between the two points in kilometers.
 */
function calculateDistance(point1: GeoPoint, point2: GeoPoint): number {
  const R = 6371; // Radius of the Earth in kilometers
  const dLat = toRad(point2.latitude - point1.latitude);
  const dLon = toRad(point2.longitude - point1.longitude);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(point1.latitude)) *
      Math.cos(toRad(point2.latitude)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c; // Distance in kilometers
}

/**
 * Converts a numeric value from degrees to radians.
 *
 * @param {number} value - The value in degrees to be converted to radians.
 * @returns {number} The value converted to radians.
 */
function toRad(value: number): number {
  return (value * Math.PI) / 180;
}

/**
 * Sends a notification to the user regarding significant earthquakes.
 *
 * @param {string} token - The user's FCM token.
 * @param {EarthquakeFeature} earthquakes - The earthquake data to notify about.
 * @param {FirebaseFirestore.QueryDocumentSnapshot} userDoc -
 * The Firestore document of the user.
 * @returns {Promise<void>} A promise that resolves when the
 * notification is sent.
 */
export async function earthquakeNotification(
  token: string,
  earthquakes: EarthquakeFeature,
  userDoc: FirebaseFirestore.QueryDocumentSnapshot
) {
  const payload = {
    notification: {
      title: "Earthquake Alert!",
      body: `An earthquake of magnitude 
        ${earthquakes.properties.mag} occurred at
        ${earthquakes.properties.place}.`,
      sound: "default",
    },
    token: token,
  };

  // const promises = earthquakes.map(async (earthquake) => {
  //   const payload = {
  //     notification: {
  //       title: "Earthquake Alert!",
  //       body: `An earthquake of magnitude
  //       ${earthquake.magnitude} occurred at ${earthquake.place}.`,
  //     },
  //     token: userData.token,
  //     // Assume you store user Firebase Cloud Messaging token
  //   };

  //   // Use Firebase Cloud Messaging to send the notification
  //   return admin.messaging().send(payload);
  // });

  try {
    await admin.messaging().send(payload);
    console.log(
      `Notification sent to ${token} for earthquake:
      ${earthquakes.properties.place}.`
    );
  } catch (error) {
    console.error(`Error sending notification to ${token}:`, error);
    if (error instanceof Error&& (error as any).code ===
    "messaging/invalid-registration-token" || (error as any).code ===
    "messaging/registration-token-not-registered") {
      console.log(`Removing invalid token: ${token}`);
      await db.collection("users").doc(userDoc.id).update(
        {token: admin.firestore.FieldValue.delete()}
      );
    }
  }
}

/**
 * Fetches data from the given URL with retries.
 *
 * @param {string} url - The URL to fetch data from.
 * @param {number} [retries=3] - The number of retry attempts.
 * @return {Promise<any>} A promise that resolves with the fetched data.
 */
async function fetchWithRetries(
  url: string,
  retries = 3): Promise<any> {
  for (let i = 0; i < retries; i++) {
    try {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`Error fetching data: ${response.statusText}`);
      }
      return await response.json();
    } catch (error) {
      console.error(`Attempt ${i + 1} failed:`, error);
      if (i === retries - 1) throw error;
    }
  }
}
/**
 * Adds dummy earthquake data to Firestore.
 *
 * This function is triggered by an HTTP request and adds
 * a dummy earthquake data entry to the Firestore database.
 *
 * @param {express.Request} req - The HTTP request object.
 * @param {express.Response} res - The HTTP response object.
 */
export const addDummyEarthquakeData = functions.https.onRequest(
  async (req, res) => {
    try {
      // Dummy earthquake data
      const earthquakeData = {
        id: "us7000pz55",
        properties: {
          place: "65km N of Lucknow, India",
          mag: 6.0, // Example magnitude value
          time: Date.now(),
        },
        geometry: {
          coordinates: [80.9462, 26.8467],
          // Example coordinates for New Delhi, India
        },
      };

      // Check if the magnitude is greater than 4
      if (earthquakeData.properties.mag > 4) {
        // Store the earthquake data in Firestore
        await admin.firestore().collection("disasters").doc(
          earthquakeData.id).set({
          type: "earthquake",
          description: earthquakeData.properties.place,
          location: new admin.firestore.GeoPoint(
            earthquakeData.geometry.coordinates[1],
            earthquakeData.geometry.coordinates[0]
          ),
          magnitude: earthquakeData.properties.mag,
          timestamp: admin.firestore.Timestamp.fromMillis(
            earthquakeData.properties.time
          ),
          updatedAt: admin.firestore.Timestamp.now(),
        });

        console.log("Dummy earthquake data added successfully.");
        // // send push notification to users
        // const significantEarthquakes =
        // await db.collection("disasters").get();
        // const earthquakes: EarthquakeFeature[] =
        // significantEarthquakes.docs.map((doc) => {
        //   const data = doc.data();
        //   return {
        //     id: doc.id,
        //     properties: {
        //       place: data.place,
        //       mag: data.magnitude,
        //       time: data.timestamp.toMillis(),
        //     },
        //     geometry: {
        //       coordinates: [data.location.longitude, data.location.latitude],
        //     },
        //   };
        // });
        // await fetchAndProcessAlerts(earthquakes);
        const payload = {
          notification: {
            title: "Earthquake Alert!",
            body: `A magnitude ${earthquakeData.properties.mag} earthquake
            occurred at ${earthquakeData.properties.place}.`,
            sound: "warning_sound",
          },
          topic: "earthquake-alerts",
        };
        try {
          await admin.messaging().send(payload);
          console.log("Push notification sent successfully.");
        } catch (notificationError) {
          console.error("Error sending push notification:", notificationError);
        }
        res.status(201).send("Dummy earthquake data added successfully.");
      } else {
        console.log("Magnitude is not greater than 4, data not added.");
        res.status(400).send(
          "Dummy earthquake data mag is not more than 4, data not added."
        );
      }
    } catch (error) {
      console.error("Error adding dummy earthquake data:", error);
      res.status(500).send("Internal Server Error");
    }
  });
