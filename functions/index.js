const admin = require("firebase-admin");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {setGlobalOptions} = require("firebase-functions/v2");

admin.initializeApp();

setGlobalOptions({
  region: "asia-south1",
  maxInstances: 10,
});

const db = admin.firestore();

/* ============================================================
   1. NEW SHOP SUBMITTED -> ADMIN
============================================================ */
exports.notifyAdminOnNewShop = onDocumentCreated(
    "shops/{shopId}",
    async (event) => {
      try {
        const shop = event.data.data();

        if (shop.status !== "pending") {
          return;
        }

        const adminSnapshot = await db
            .collection("users")
            .where("role", "==", "Admin")
            .get();

        if (adminSnapshot.empty) {
          console.log("No admin found");
          return;
        }

        const tokens = [];
        adminSnapshot.forEach((doc) => {
          const data = doc.data();
          if (data.fcmToken) {
            tokens.push(data.fcmToken);
          }
        });

        if (tokens.length === 0) {
          console.log("No admin FCM tokens");
          return;
        }

        await admin.messaging().sendEachForMulticast({
          tokens,
          notification: {
            title: "🔔 New Shop Submitted",
            body: `${shop.shop_name} submitted for review.`,
          },
        });

        await db.collection("admin_notifications").add({
          title: "New Shop Submitted",
          message: `${shop.shop_name} submitted for review.`,
          type: "shop_submission",
          shopId: event.params.shopId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log("Admin notified successfully");
      } catch (e) {
        console.error(e);
      }
    },
);

/* ============================================================
   2. SHOP APPROVED -> SHOPKEEPER
============================================================ */
exports.notifyShopApproved = onDocumentUpdated(
    "shops/{shopId}",
    async (event) => {
      try {
        const before = event.data.before.data();
        const after = event.data.after.data();

        if (
          before.status === after.status ||
        after.status !== "verified"
        ) {
          return;
        }

        const userSnapshot = await db
            .collection("users")
            .where("email", "==", after.owner_email)
            .limit(1)
            .get();

        if (userSnapshot.empty) {
          console.log("Shopkeeper not found");
          return;
        }

        const userDoc = userSnapshot.docs[0];
        const user = userDoc.data();

        if (!user.fcmToken) {
          console.log("FCM token missing");
          return;
        }

        await admin.messaging().send({
          token: user.fcmToken,
          notification: {
            title: "✅ Shop Approved",
            body: "Your shop has been approved.",
          },
        });

        await db.collection("shopkeeper_notifications").add({
          uid: user.uid,
          title: "Shop Approved",
          message: "Your shop has been approved.",
          type: "shop_approved",
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log("Approval notification sent");
      } catch (e) {
        console.error(e);
      }
    },
);

/* ============================================================
   3. SHOP REJECTED -> SHOPKEEPER
============================================================ */
exports.notifyShopRejected = onDocumentUpdated(
    "shops/{shopId}",
    async (event) => {
      try {
        const before = event.data.before.data();
        const after = event.data.after.data();

        if (
          before.status === after.status ||
        after.status !== "rejected"
        ) {
          return;
        }

        const userSnapshot = await db
            .collection("users")
            .where("email", "==", after.owner_email)
            .limit(1)
            .get();

        if (userSnapshot.empty) {
          console.log("Shopkeeper not found");
          return;
        }

        const userDoc = userSnapshot.docs[0];
        const user = userDoc.data();

        if (!user.fcmToken) {
          console.log("FCM token missing");
          return;
        }

        await admin.messaging().send({
          token: user.fcmToken,
          notification: {
            title: "❌ Shop Rejected",
            body: "Your shop has been rejected.",
          },
        });

        await db.collection("shopkeeper_notifications").add({
          uid: user.uid,
          title: "Shop Rejected",
          message: "Your shop has been rejected.",
          type: "shop_rejected",
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log("Rejection notification sent");
      } catch (e) {
        console.error(e);
      }
    },
);