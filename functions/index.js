const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// Function to calculate distance between two coordinates using Haversine formula
function calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371; // Radius of the earth in km
    const dLat = deg2rad(lat2 - lat1);
    const dLon = deg2rad(lon2 - lon1);
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distance = R * c; // Distance in km
    return distance;
}

function deg2rad(deg) {
    return deg * (Math.PI / 180);
}

// Convert "lat,lng" string to {lat: number, lng: number} object
function parseLocation(locationString) {
    const [lat, lng] = locationString.split(',').map(Number);
    return { lat, lng };
}

const compatibleBloodGroups = {
    'A+': ['A+', 'A-', 'O+', 'O-'],
    'A-': ['A-', 'O-'],
    'B+': ['B+', 'B-', 'O+', 'O-'],
    'B-': ['B-', 'O-'],
    'AB+': ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'],
    'AB-': ['A-', 'B-', 'AB-', 'O-'],
    'O+': ['O+', 'O-'],
    'O-': ['O-']
};

exports.request = functions.https.onCall({
    region: "asia-south1",
}, async (data, context) => {
    try {
        let userId = context.auth?.uid;

        if (!userId && data.userId) {
            userId = data.userId;
        }

        functions.logger.info(`[DEBUG] Starting request processing`);
        functions.logger.info(`[DEBUG] Request from user ID: ${userId}`);
        
        // Log only the relevant parts of the request data
        functions.logger.info(`[DEBUG] Request data:
            Blood Group: ${data.data?.bloodGroup}
            Units: ${data.data?.units}
            Hospital: ${data.data?.hospital}
            Location: ${data.data?.location}
            Name: ${data.data?.name}
            Phone: ${data.data?.phone}
        `);

        if (!userId) {
            functions.logger.warn("[DEBUG] No authenticated user found. Using request data without user association.");
        }

        const {
            name,
            bloodGroup,
            units,
            date,
            time,
            gender,
            hospital,
            location,
            phone
        } = data.data;

        // Log request details
        functions.logger.info(`[DEBUG] Request details:
            Blood Group: ${bloodGroup}
            Units: ${units}
            Hospital: ${hospital}
            Location: ${location}
            Name: ${name}
            Phone: ${phone}
        `);

        if (!bloodGroup || !location || !hospital) {
            let missingFields = [];
            if (!bloodGroup) missingFields.push("bloodGroup");
            if (!location) missingFields.push("location");
            if (!hospital) missingFields.push("hospital");

            throw new functions.https.HttpsError(
                'invalid-argument',
                `Missing required fields: ${missingFields.join(", ")}`
            );
        }

        const locationString = await getCoordinatesFromAddress(location);
        functions.logger.info(`[DEBUG] Parsed location coordinates: ${locationString}`);

        const requestLocation = parseLocation(locationString);
        functions.logger.info(`[DEBUG] Request location object: ${JSON.stringify({
            lat: requestLocation.lat,
            lng: requestLocation.lng
        })}`);

        // Maximum distance in kilometers for nearby users
        const MAX_DISTANCE = 50;

        // Get compatible blood types that can donate to the requested blood group
        const compatibleDonors = compatibleBloodGroups[bloodGroup] || [];
        functions.logger.info(`[DEBUG] Compatible blood types for ${bloodGroup}: ${JSON.stringify(compatibleDonors)}`);

        // Get the requester's user ID
        const requesterId = context.auth?.uid || data.userId || data.data?.userId;
        functions.logger.info(`[DEBUG] ===== REQUESTER ID DETAILS =====
            Context Auth: ${context.auth ? 'Present' : 'Missing'}
            Context UID: ${context.auth?.uid || 'undefined'}
            Data UserId: ${data.userId || 'undefined'}
            Data.Data UserId: ${data.data?.userId || 'undefined'}
            Final RequesterId: ${requesterId || 'undefined'}
            Request Data: ${JSON.stringify({
                name: data.data?.name,
                bloodGroup: data.data?.bloodGroup,
                hospital: data.data?.hospital,
                userId: data.data?.userId
            })}
        =================================`);

        if (!requesterId) {
            functions.logger.error('[DEBUG] No requester ID found in context or data');
            throw new functions.https.HttpsError(
                'failed-precondition',
                'No user ID found in request'
            );
        }

        // Query users collection for potential donors
        const usersSnapshot = await admin.firestore()
            .collection('users')
            .where('isDonor', '==', true)
            .get();

        functions.logger.info(`[DEBUG] Found ${usersSnapshot.size} potential donors in database`);

        // Filter users based on blood compatibility and distance
        const nearbyUsers = [];
        let totalUsersChecked = 0;
        let skippedUsers = 0;
        let compatibleUsers = 0;

        usersSnapshot.forEach(doc => {
            totalUsersChecked++;
            const userData = doc.data();
            
            functions.logger.info(`[DEBUG] Processing user ${doc.id}:
                isDonor: ${userData.isDonor}
                bloodType: ${userData.bloodType}
                hasFCMToken: ${!!userData.fcmToken}
                hasLocation: ${!!userData.location}
                isRequester: ${doc.id === requesterId}
            `);

            // Skip users without FCM token
            if (!userData.fcmToken) {
                functions.logger.info(`[DEBUG] Skipping user ${doc.id} - No FCM token`);
                skippedUsers++;
                return;
            }

            // Skip if this user is the requester (exact UID match)
            if (doc.id === requesterId) {
                functions.logger.info(`[DEBUG] SKIPPING REQUESTER - User ${doc.id} matches requester ID ${requesterId}`);
                skippedUsers++;
                return;
            }

            // Skip if not a donor
            if (!userData.isDonor) {
                functions.logger.info(`[DEBUG] Skipping user ${doc.id} - Not a donor`);
                skippedUsers++;
                return;
            }

            // Check blood compatibility
            if (!compatibleDonors.includes(userData.bloodType)) {
                functions.logger.info(`[DEBUG] Skipping user ${doc.id} - Incompatible blood type ${userData.bloodType} (needed: ${bloodGroup})`);
                skippedUsers++;
                return;
            }

            compatibleUsers++;
            functions.logger.info(`[DEBUG] Found compatible donor: ${doc.id}, blood type: ${userData.bloodType}`);

            if (!userData.location) {
                functions.logger.info(`[DEBUG] Skipping user ${doc.id} - No location data`);
                skippedUsers++;
                return;
            }

            const userLocation = parseLocation(userData.location);
            functions.logger.info(`[DEBUG] User ${doc.id} location: ${JSON.stringify({
                lat: userLocation.lat,
                lng: userLocation.lng
            })}`);

            const distance = calculateDistance(
                requestLocation.lat,
                requestLocation.lng,
                userLocation.lat,
                userLocation.lng
            );

            functions.logger.info(`[DEBUG] Distance for user ${doc.id}: ${distance}km (max allowed: ${MAX_DISTANCE}km)`);

            if (distance <= MAX_DISTANCE) {
                // Triple check this is not the requester before adding to nearbyUsers
                if (doc.id !== requesterId) {
                    nearbyUsers.push({
                        fcmToken: userData.fcmToken,
                        userId: doc.id,
                        distance: distance.toFixed(1),
                        platform: userData.platform,
                        deviceType: userData.deviceType,
                        isRequester: false
                    });
                    functions.logger.info(`[DEBUG] Added eligible donor ${doc.id} to nearby users list (distance: ${distance.toFixed(1)}km)`);
                } else {
                    functions.logger.info(`[DEBUG] SKIPPING REQUESTER - User ${doc.id} passed distance check but is requester`);
                }
            } else {
                functions.logger.info(`[DEBUG] Skipping user ${doc.id} - Too far (${distance}km > ${MAX_DISTANCE}km)`);
                skippedUsers++;
            }
        });

        functions.logger.info(`[DEBUG] Final Statistics:
            Total users checked: ${totalUsersChecked}
            Skipped users: ${skippedUsers}
            Compatible users found: ${compatibleUsers}
            Nearby users to notify: ${nearbyUsers.length}
            Nearby users details: ${JSON.stringify(nearbyUsers.map(u => ({userId: u.userId, distance: u.distance})))}
        `);

        // Store the blood request in Firestore
        const requestRef = await admin.firestore().collection('bloodRequests').add({
            name,
            bloodGroup,
            units,
            date,
            time,
            gender,
            hospital,
            location: locationString,
            phone,
            requestedBy: userId || 'anonymous',
            // createdAt: admin.firestore.FieldValue.serverTimestamp(),
            status: 'active'
        });

        const requestId = requestRef.id;

        // Send notifications to nearby users
        const notificationPromises = nearbyUsers.map(user => {
            functions.logger.info(`[DEBUG] Preparing notification for user ${user.userId}:
                Distance: ${user.distance}km
                FCM Token: ${user.fcmToken}
            `);

            const message = {
                notification: {
                    title: `${bloodGroup} Blood Required`,
                    body: `${units} units needed at ${hospital}`
                },
                data: {
                    requestId: String(requestId),
                    bloodGroup: String(bloodGroup),
                    hospital: String(hospital),
                    units: String(units),
                    patientName: String(name || ""),
                    patientGender: String(gender || ""),
                    requestDate: String(date || ""),
                    requestTime: String(time || ""),
                    requestLocation: String(location || ""),
                    requestPhone: String(phone || ""),
                    distance: String(user.distance),
                    click_action: 'FLUTTER_NOTIFICATION_CLICK',
                    screen: '/bloodRequestDetails',
                    actionType: 'blood_request',
                    hasActions: 'true',
                    acceptAction: 'ACCEPT_BLOOD_REQUEST',
                    rejectAction: 'REJECT_BLOOD_REQUEST'
                },
                android: {
                    priority: 'high',
                    notification: {
                        click_action: 'FLUTTER_NOTIFICATION_CLICK',
                        default_sound: true,
                        default_vibrate_timings: true,
                        visibility: 'PUBLIC',
                        priority: 'max',
                        channel_id: "blood_requests"
                    }
                },
                apns: {
                    payload: {
                        aps: {
                            sound: 'default',
                            badge: 1,
                            category: 'BLOOD_REQUEST_CATEGORY',
                            content_available: true,
                            'mutable-content': 1
                        }
                    }
                },
                token: user.fcmToken
            };

            // Log detailed notification button status
            functions.logger.info(`[DEBUG] Notification Button Status for user ${user.userId}:
                User ID: ${user.userId}
                Distance: ${user.distance}km
                hasActions: ${message.data.hasActions}
                acceptAction: ${message.data.acceptAction}
                rejectAction: ${message.data.rejectAction}
                FCM Token: ${user.fcmToken}
                Platform: ${user.platform || 'unknown'}
                Device Type: ${user.deviceType || 'unknown'}
                Is Requester: ${user.userId === requesterId}
                Data Payload: ${JSON.stringify(message.data)}
                Android Category: ${message.android.notification.category}
                iOS Category: ${message.apns.payload.aps.category}
            `);

            return admin.messaging().send(message)
                .then(() => {
                    functions.logger.info(`[DEBUG] Successfully sent notification with buttons to user ${user.userId}`);
                })
                .catch((error) => {
                    functions.logger.error(`[DEBUG] Error sending notification to user ${user.userId}: ${error}`);
                    throw error;
                });
        });

        // Log final notification status
        functions.logger.info(`[DEBUG] Final Notification Status:
            Total notifications to send: ${nearbyUsers.length}
            Users receiving buttons: ${nearbyUsers.length}
            Notification details:
            ${nearbyUsers.map(user => `
                User: ${user.userId}
                Distance: ${user.distance}km
                FCM Token: ${user.fcmToken}
            `).join('\n')}
        `);

        // Wait for all notifications to be sent
        // await Promise.all(notificationPromises);

        functions.logger.info(`[DEBUG] All notifications sent successfully. Total sent: ${nearbyUsers.length}`);

        return {
            success: true,
            notificationsSent: nearbyUsers.length,
            requestId
        };
    } catch (error) {
        functions.logger.error('Error sending notifications:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// Helper function to get coordinates from an address if needed
async function getCoordinatesFromAddress(address) {
    try {
        if (/^-?\d+(\.\d+)?,-?\d+(\.\d+)?$/.test(address)) {
            return address;
        }

        // Import the fetch package
        const fetch = require('node-fetch');

        // Encode the address for URL
        const encodedAddress = encodeURIComponent(address);

        // Make request to OSM Nominatim API
        // Add a custom User-Agent as required by Nominatim Usage Policy
        const response = await fetch(
            `https://nominatim.openstreetmap.org/search?q=${encodedAddress}&format=json&limit=1`,
            {
                headers: {
                    'User-Agent': 'RhinoRaktDoors/1.0'
                }
            }
        );

        if (!response.ok) {
            throw new Error(`Geocoding API error: ${response.statusText}`);
        }

        const data = await response.json();

        // Check if the API returned valid results
        if (!data || data.length === 0) {
            throw new Error('No results found for this address');
        }

        // Extract coordinates from the first result
        const lat = data[0].lat;
        const lon = data[0].lon;

        // Return in the format "lat,lng"
        return `${lat},${lon}`;
    } catch (error) {
        functions.logger.error('Error in getCoordinatesFromAddress:', error);
        return null;
    }
}