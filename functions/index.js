const { setGlobalOptions } = require("firebase-functions");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

setGlobalOptions({ maxInstances: 10 });


// =====================================================
// 1. NEW SHOP → ADMIN NOTIFICATION
// =====================================================

exports.newShopNotification = onDocumentCreated(
  "shops/{shopId}",
  async (event) => {
    const shop = event.data.data();

    if (!shop) return;

    const shopName = shop.shop_name || "New Shop";

    // Find all admins
    const adminsSnapshot = await db
      .collection("users")
      .where("role", "==", "Admin")
      .get();

    if (adminsSnapshot.empty) {
      console.log("No admin users found.");
      return;
    }

    const tokens = [];

    adminsSnapshot.forEach((doc) => {
      const data = doc.data();

      if (data.fcmToken) {
        tokens.push(data.fcmToken);
      }
    });

    // Save notification in admin_notifications
    await db.collection("admin_notifications").add({
      title: "New Shop Submitted",
      message: `${shopName} is waiting for your review.`,
      type: "shop_review",
      shopId: event.params.shopId,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Send push notification
    if (tokens.length > 0) {
      await messaging.sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "New Shop Submitted",
          body: `${shopName} is waiting for your review.`,
        },
        data: {
          type: "shop_review",
          shopId: event.params.shopId,
        },
      });
    }

    console.log("New shop notification sent to admin.");
  }
);


// =====================================================
// 2. SHOP APPROVED / REJECTED → SHOPKEEPER
// =====================================================

exports.shopStatusNotification = onDocumentUpdated(
  "shops/{shopId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    if (!before || !after) return;

    const oldStatus = before.status;
    const newStatus = after.status;

    // Only run when status actually changes
    if (oldStatus === newStatus) return;

    // Only handle verified/rejected
    if (newStatus !== "verified" && newStatus !== "rejected") {
      return;
    }

    const ownerUid = after.ownerUid;

    if (!ownerUid) {
      console.log("ownerUid missing from shop.");
      return;
    }

    // Get shopkeeper user
    const userDoc = await db.collection("users").doc(ownerUid).get();

    if (!userDoc.exists) {
      console.log("Shopkeeper user not found:", ownerUid);
      return;
    }

    const userData = userDoc.data();
    const fcmToken = userData.fcmToken;

    const shopName = after.shop_name || "Your shop";

    let title;
    let message;
    let type;

    if (newStatus === "verified") {
      title = "Shop Approved";
      message = `Congratulations! ${shopName} has been approved.`;
      type = "shop_approved";
    } else {
      title = "Shop Rejected";
      message = `${shopName} has been rejected.`;
      type = "shop_rejected";
    }

    // Save notification inside Firestore
    await db.collection("shopkeeper_notifications").add({
      userId: ownerUid,
      title: title,
      message: message,
      type: type,
      shopId: event.params.shopId,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Send FCM push notification
    if (fcmToken) {
      await messaging.send({
        token: fcmToken,
        notification: {
          title: title,
          body: message,
        },
        data: {
          type: type,
          shopId: event.params.shopId,
        },
      });

      console.log("Shopkeeper notification sent.");
    } else {
      console.log("FCM token not found for:", ownerUid);
    }
  }
);