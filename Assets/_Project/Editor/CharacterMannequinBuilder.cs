using UnityEditor;
using UnityEngine;
using Wolf.Core;

namespace Wolf.EditorTools
{
    /// <summary>
    /// Builds an articulated primitive mannequin per faction at prefab-build
    /// time: victims read as civilians (jacket + backpack), psychos get glowing
    /// implant eyes, a jaw plate and an arm blade, mercs get a neon visor and
    /// armor pads. These are the default bodies until real character models
    /// are dropped into Resources/CharacterModels (see CharacterModelSlot) —
    /// actual Cyberpunk-2077 game models are CDPR's copyrighted assets and are
    /// not shipped; the slot is the legal path to photoreal characters
    /// (Mixamo, store packs, licensed Sketchfab downloads).
    /// Character forward is +Z, so face gear sits at positive Z.
    /// </summary>
    internal static class CharacterMannequinBuilder
    {
        internal static GameObject Attach(GameObject root, FactionType faction)
        {
            var man = new GameObject("Mannequin");
            man.transform.SetParent(root.transform, false);

            Material cloth = PhotorealForge.Load(PhotorealForge.BodyClothMat);
            Material armor = PhotorealForge.Load(PhotorealForge.BodyArmorMat);
            Material rust = PhotorealForge.Load(PhotorealForge.BodyRustMat);
            Material metal = PhotorealForge.Load(PhotorealForge.DarkMetalMat);
            Material body = faction == FactionType.Killer ? armor : faction == FactionType.Cannibal ? rust : cloth;

            // Capsule root pivot is at its centre: feet are at local y -1.
            Part(man, PrimitiveType.Cube, new Vector3(0f, -0.05f, 0f), new Vector3(0.30f, 0.16f, 0.20f), Vector3.zero, body);   // hips
            Part(man, PrimitiveType.Cube, new Vector3(0f, 0.28f, 0f), new Vector3(0.34f, 0.52f, 0.22f), Vector3.zero, body);    // torso
            Part(man, PrimitiveType.Sphere, new Vector3(0f, 0.66f, 0f), Vector3.one * 0.26f, Vector3.zero, body);               // head
            Part(man, PrimitiveType.Capsule, new Vector3(-0.24f, 0.22f, 0f), new Vector3(0.16f, 0.26f, 0.16f), new Vector3(0f, 0f, 8f), body);   // L arm
            Part(man, PrimitiveType.Capsule, new Vector3(0.24f, 0.22f, 0f), new Vector3(0.16f, 0.26f, 0.16f), new Vector3(0f, 0f, -8f), body);   // R arm
            Part(man, PrimitiveType.Capsule, new Vector3(-0.10f, -0.55f, 0f), new Vector3(0.17f, 0.40f, 0.17f), Vector3.zero, body);             // L leg
            Part(man, PrimitiveType.Capsule, new Vector3(0.10f, -0.55f, 0f), new Vector3(0.17f, 0.40f, 0.17f), Vector3.zero, body);              // R leg

            switch (faction)
            {
                case FactionType.Survivor:
                    Part(man, PrimitiveType.Cube, new Vector3(0f, 0.30f, -0.19f), new Vector3(0.26f, 0.34f, 0.12f), Vector3.zero, cloth); // backpack (on the back, -Z)
                    break;

                case FactionType.Cannibal:
                {
                    Material eyes = PhotorealForge.Load(PhotorealForge.NeonRedMat);
                    Part(man, PrimitiveType.Sphere, new Vector3(-0.055f, 0.68f, 0.115f), Vector3.one * 0.05f, Vector3.zero, eyes);
                    Part(man, PrimitiveType.Sphere, new Vector3(0.055f, 0.68f, 0.115f), Vector3.one * 0.05f, Vector3.zero, eyes);
                    Part(man, PrimitiveType.Cube, new Vector3(0f, 0.58f, 0.11f), new Vector3(0.14f, 0.06f, 0.08f), Vector3.zero, metal);   // jaw plate
                    Part(man, PrimitiveType.Cube, new Vector3(0.30f, 0.10f, 0.02f), new Vector3(0.04f, 0.42f, 0.12f), new Vector3(0f, 0f, -18f), metal); // arm blade
                    break;
                }

                case FactionType.Killer:
                {
                    Material visor = PhotorealForge.Load(PhotorealForge.NeonCyanMat);
                    Part(man, PrimitiveType.Cube, new Vector3(0f, 0.68f, 0.115f), new Vector3(0.18f, 0.045f, 0.05f), Vector3.zero, visor);
                    Part(man, PrimitiveType.Cube, new Vector3(-0.26f, 0.46f, 0f), new Vector3(0.14f, 0.08f, 0.18f), Vector3.zero, metal); // pads
                    Part(man, PrimitiveType.Cube, new Vector3(0.26f, 0.46f, 0f), new Vector3(0.14f, 0.08f, 0.18f), Vector3.zero, metal);
                    break;
                }
            }

            return man;
        }

        private static void Part(GameObject parent, PrimitiveType type, Vector3 pos, Vector3 scale, Vector3 euler, Material mat)
        {
            GameObject part = GameObject.CreatePrimitive(type);
            // Visual-only: the CharacterController capsule handles all physics.
            Object.DestroyImmediate(part.GetComponent<Collider>());
            part.transform.SetParent(parent.transform, false);
            part.transform.localPosition = pos;
            part.transform.localScale = scale;
            part.transform.localEulerAngles = euler;
            if (mat != null)
            {
                part.GetComponent<Renderer>().sharedMaterial = mat;
            }
        }
    }
}
