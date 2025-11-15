# README: Why We Switched from In-Cluster PostgreSQL to Amazon RDS

## TL;DR

We moved our PostgreSQL database **out of the EKS cluster** (where it was running as a StatefulSet) and migrated it to **Amazon RDS for PostgreSQL**. This was done for **reliability, performance, scalability, and easier management**.

---

## 1. The Old Setup: In-Cluster PostgreSQL (StatefulSet)

Initially, our PostgreSQL database was running **inside the Kubernetes cluster** as a StatefulSet. This setup used an **EBS-backed Persistent Volume** to store data.

**Pros:**

* Easy to set up.
* Everything (app + DB) ran inside EKS.

**Cons:**

* If the node running the DB pod went down, recovery took time.
* Manual backups and restores.
* Scaling vertically or horizontally was complex.
* Security and networking were more fragile (DB shared cluster network space).
* We were managing the database ourselves (patches, maintenance, monitoring, etc.).

---

## 2. The New Setup: Amazon RDS for PostgreSQL

Now, PostgreSQL runs in **Amazon RDS**, which is a **fully managed database service** by AWS.

**Pros:**

* **Automated backups** and easy restores.
* **High availability** (Multi-AZ support).
* **Performance tuning** handled by AWS.
* **Easy scaling** (storage, CPU, memory).
* **Built-in monitoring** via CloudWatch.
* **Separate failure domain** - DB issues don't affect our EKS cluster.
* **More secure** - VPC isolation, IAM integration, and encryption at rest/in transit.

**Cons:**

* Slightly more cost than self-managed DB (but worth it).
* Initial migration step required some setup.

---

## 3. What Changed in the Configuration

- **Removed:** The `StatefulSet` and `Service` for in-cluster Postgres.
- **Added:** An external connection string to the RDS instance.
- **Updated:** The Kubernetes secret `postgres-secret` to store the new RDS connection URL.
- **Application Deployment:** Now references the secret for– `DATABASE_URL`, which points to RDS.

Example snippet:

```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: DATABASE_URL
```

This means the app now connects directly to RDS instead of the old in-cluster Postgres.

---

## 4. Migration Process (In Short)

1. Exported data from the old Postgres using `pg_dump`.
2. Imported the dump into RDS using `psql`.
3. Updated app secrets with new RDS credentials and endpoint.
4. Deployed the new app version.
5. Verified connection and deleted the old StatefulSet.

---

## 5. Why This Matters (for You, Boss 🧠)

* **No more database babysitting.** AWS handles updates, patches, and backups.
* **Less downtime risk.** RDS automatically fails over if a node crashes.
* **Better performance.** AWS optimizes the underlying infrastructure.
* **More secure and compliant.** Encryption, IAM, and isolated networking.
* **Simpler scaling.** If our app grows, the database can scale without downtime.

In short: we now have a **production-grade, resilient, managed database**, freeing us to focus on building features instead of managing servers.

---

## 6. Next Steps

* Monitor RDS performance in the AWS Console.
* Set up CloudWatch alarms for DB CPU, storage, and connection counts.
* Optionally enable Multi-AZ for even higher availability.

---

**Summary:**

> We moved Postgres to RDS to make our system more reliable, faster, and easier to manage. Less firefighting, more feature building.
