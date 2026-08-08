'use strict';
// ---------------------------------------------------------------------
// The four places of chapter I. Each zone builds its own geometry, its own
// collider set and its own list of things you can walk up to and press E on.
// Progression: деревня → крипта (герб + ключ) → мельница (второй герб) →
// ворота → усадьба → Морана.
// ---------------------------------------------------------------------

function putItem(W, id, item, count, x, z, y) {
  const mesh = pickupMesh(W, x, z, item, y);
  W.interact({ id, kind: 'pickup', item, count: count || 1, x, z, y: y == null ? 0.55 : y, mesh,
               label: (ITEMS[item] ? ITEMS[item].name : item) + (count > 1 ? ` ×${count}` : '') });
}

function putKey(W, id, key, x, z, y) {
  const mesh = pickupMesh(W, x, z, key, y);
  W.interact({ id, kind: 'keyPickup', key, x, z, y: y == null ? 0.75 : y, mesh, label: KEY_ITEMS[key].name });
}

function putNote(W, id, note, x, z, y) {
  const m = meshBox(0.34, 0.02, 0.26, new THREE.MeshBasicMaterial({ color: 0xd8c8a6 }));
  place(m, x, y == null ? 1.0 : y, z, rnd() * 0.6);
  W.add(m);
  W.interact({ id, kind: 'note', note, x, z, y: y == null ? 1.0 : y, mesh: m, label: 'Прочитать: ' + NOTES[note].title });
}

function putContainer(W, id, x, z, loot, label, mesh) {
  W.interact({ id, kind: 'container', x, z, y: 0.7, loot, label: label || 'Обыскать', mesh: mesh || null });
}

const ZONES = {

  // ================================================================ village
  village: {
    id: 'village', name: 'Волчий Лог', outdoor: true,
    fog: { color: 0x070a10, density: 0.030 },
    ambient: { color: 0x2b3346, intensity: 0.40 }, moon: 0.34, tension: 0.10,
    hint: 'Дочь увезли в усадьбу на холме. Ворота заперты гербом.',

    build(W) {
      srand(20250808);
      ground(W, 0, 0, 96, 96, mat('snow'));
      // the road — the only clean line in the whole village
      const road = ground(W, 0, 2, 5.5, 68, mat('dirt'), 0.015);
      road.renderOrder = 1;

      // outer bound: you are hemmed in by snowdrifts and dead pines
      for (const [x, z, hw, hd] of [[0, -37, 40, 3], [0, 37, 40, 3], [-37, 0, 3, 40], [37, 0, 3, 40]]) {
        W.solid(box(x, z, hw, hd, 0, 6));
      }
      for (let i = 0; i < 46; i++) {
        const a = (i / 46) * TAU + rnd() * 0.1;
        const r = 30 + rnd() * 5;
        const x = Math.cos(a) * r, z = Math.sin(a) * r;
        if (Math.abs(x) < 4 && z > 20) continue;                 // keep the road mouth clear
        (rnd() < 0.7 ? tree : deadTree)(W, x, z, rndRange(0.8, 1.4));
      }
      for (let i = 0; i < 14; i++) {
        const x = rndRange(-28, 28), z = rndRange(-26, 28);
        if (dist(x, z, 0, 0) < 9) continue;
        deadTree(W, x, z, rndRange(0.6, 1.0));
      }

      // ---- the square
      bonfire(W, 0, 0);
      well(W, 4.5, -4);
      shrine(W, -5.5, 4.5);
      W.interact({ id: 'vil_shrine', kind: 'shrine', x: -5.5, z: 5.4, y: 1.2, label: 'Помолиться (сохранить игру)' });

      // ---- merchant
      cart(W, 10, 9.5, -0.5);
      torch(W, 8.4, 0, 8.2);
      W.interact({ id: 'vil_merchant', kind: 'merchant', x: 10.6, z: 10.6, y: 1.4, label: 'Ворон, скупщик' });
      W.merchantAt = { x: 11.6, z: 11.2, yaw: yawToward(-1.6, -1.7) };

      // ---- houses
      const houses = [[-18, -4, 0], [-20, 12, 0.4], [14, -10, -0.3], [18, 18, 0.2], [-9, 20, 0.1], [11, -17, 0.6]];
      for (const [x, z, ry] of houses) house(W, x, z, 8, 7, 4.2, ry, { lit: rnd() < 0.3 });
      for (const [x, z] of [[-14, 2], [16, 4], [-6, 14], [6, -9]]) fence(W, x - 3, z, x + 3, z);

      // ---- church + graveyard (west-south), the way down into the crypt
      house(W, -13, -22, 12, 10, 6.0, 0, {});
      const cross = meshBox(0.3, 2.2, 0.3, mat('woodDark'));
      place(cross, -13, 8.2, -22); W.add(cross);
      const crossArm = meshBox(1.3, 0.3, 0.3, mat('woodDark'));
      place(crossArm, -13, 8.6, -22); W.add(crossArm);
      torch(W, -10.4, 0, -16.4); torch(W, -15.6, 0, -16.4);
      for (let i = 0; i < 12; i++) grave(W, -22 + (i % 4) * 2.2, -26 + Math.floor(i / 4) * 2.6);
      fence(W, -25, -14, -6, -14);
      W.interact({ id: 'vil_cryptDoor', kind: 'door', to: 'crypt', spawn: 'fromVillage',
                   lock: 'cryptKey', lockedText: 'Дверь в крипту заперта церковным ключом',
                   x: -13, z: -16.6, y: 1.2, label: 'Спуститься в крипту' });

      // the huntsman who did not make it back, and his key
      const corpse = meshBox(0.6, 0.35, 1.7, mat('cloth'));
      place(corpse, -9.5, 0.18, -13.0, 0.5); W.add(corpse);
      putKey(W, 'vil_cryptKey', 'cryptKey', -9.5, -12.2, 0.6);
      putNote(W, 'vil_churchNote', 'churchNote', -10.6, -12.9, 0.55);

      // ---- mill (east), locked until the crypt gives up its key
      house(W, 24, 6, 10, 10, 6.5, 0, {});
      const wheel = new THREE.Mesh(new THREE.TorusGeometry(2.6, 0.22, 6, 16), mat('woodDark'));
      wheel.position.set(29.4, 3.0, 6); wheel.rotation.y = Math.PI / 2;
      W.add(wheel);
      torch(W, 18.2, 0, 8.6);
      W.interact({ id: 'vil_millDoor', kind: 'door', to: 'mill', spawn: 'fromVillage',
                   lock: 'millKey', lockedText: 'Дверь мельницы заперта',
                   x: 18.9, z: 6, y: 1.2, label: 'Войти на мельницу' });

      // ---- manor gate (north)
      for (const s of [-1, 1]) {
        const post = meshBox(1.4, 6.5, 1.4, mat('stone'));
        place(post, s * 3.2, 3.25, -30); W.add(post);
        W.solid(box(s * 3.2, -30, 0.8, 0.8, 0, 6.5));
      }
      const gateMesh = new THREE.Group();
      for (let i = -2; i <= 2; i++) {
        const bar = meshBox(0.14, 4.6, 0.14, mat('iron'));
        place(bar, i * 1.1, 2.3, 0); gateMesh.add(bar);
      }
      const crestPlate = new THREE.Mesh(new THREE.CircleGeometry(0.75, 16), mat('gold'));
      crestPlate.position.set(0, 2.6, 0.12); gateMesh.add(crestPlate);
      gateMesh.position.set(0, 0, -30);
      W.add(gateMesh);
      W.solid(box(0, -30, 2.6, 0.3, 0, 4.6));
      W.gateMesh = gateMesh;
      W.interact({ id: 'vil_gate', kind: 'gate', to: 'manor', spawn: 'fromVillage',
                   requires: ['crestLeft', 'crestRight'], x: 0, z: -28.6, y: 1.6,
                   label: 'Ворота усадьбы' });
      torch(W, -4.4, 0, -28.4); torch(W, 4.4, 0, -28.4);

      // ---- scattered loot
      crate(W, -16.4, 0.6); crate(W, -15.6, 1.4, 0.4);
      putContainer(W, 'vil_c1', -16, 1, [['ammo38', 6], ['casing', 2]], 'Обыскать ящики');
      barrel(W, 12.6, -13.4);
      putContainer(W, 'vil_c2', 12.6, -13.4, [['powder', 2], ['herb', 1]], 'Обыскать бочку');
      barrel(W, -21.4, 14.6);
      putContainer(W, 'vil_c3', -21.4, 14.6, [['herb', 2], ['lead', 1]], 'Обыскать бочку');
      putItem(W, 'vil_i1', 'ammo38', 8, 2.4, 12.0);
      putItem(W, 'vil_i2', 'herb', 1, -7.6, -8.4);
      putItem(W, 'vil_i3', 'powder', 1, 19.6, 16.2);
      putItem(W, 'vil_i4', 'teeth', 1, -24.4, -8.0);

      // yaw 0 looks down -Z, so every arrival faces into the village
      W.spawn('start', 0, 26, 0);
      W.spawn('fromCrypt', -13, -14.6, Math.PI);
      W.spawn('fromMill', 16.8, 6, Math.PI / 2);
      W.spawn('fromManor', 0, -26.5, Math.PI);
    },

    enemies: [
      { id: 'vil_g1', type: 'ghoul', x: 6, z: 15, patrol: [[6, 15], [-2, 18], [8, 22]] },
      { id: 'vil_g2', type: 'ghoul', x: -15, z: 7, patrol: [[-15, 7], [-19, 16], [-10, 10]] },
      { id: 'vil_g3', type: 'ghoul', x: 13, z: -6, patrol: [[13, -6], [8, -12], [17, -2]] },
      { id: 'vil_g4', type: 'ghoul', x: -4, z: -18, patrol: [[-4, -18], [-8, -24], [2, -22]] },
      { id: 'vil_v1', type: 'vurdalak', x: 19, z: 1, patrol: [[19, 1], [22, 12], [14, 6]] },
    ],
    // after both halves of the crest are in hand the village turns hostile
    waves: [{ flag: 'bothCrests', spawns: [
      { id: 'vil_w1', type: 'ghoul', x: 2, z: 8 },
      { id: 'vil_w2', type: 'ghoul', x: -6, z: -2 },
      { id: 'vil_w3', type: 'vurdalak', x: 8, z: -4 },
    ] }],
  },

  // ================================================================== crypt
  crypt: {
    id: 'crypt', name: 'Крипта', outdoor: false,
    fog: { color: 0x04050a, density: 0.075 },
    ambient: { color: 0x1a2030, intensity: 0.22 }, moon: 0.0, tension: 0.3,
    hint: 'Под церковью. В сундуке — то, что нужно воротам.',

    build(W) {
      srand(4242);
      const wallM = mat('stone'), floorM = mat('stoneDark');

      // where two rooms meet, only the wider room builds the shared wall
      room(W, 0, 0, 10, 8, { h: 3.2, wall: wallM, floor: floorM, ceil: mat('stoneDark'),
        doors: [{ side: 'w', at: 0, width: 2.4 }] });
      doorPanel(W, 0, 3.78, 0);
      room(W, -10, 0, 10, 3.2, { h: 3.2, wall: wallM, floor: floorM, ceil: mat('stoneDark'),
        open: ['e', 'w'] });
      room(W, -23, 0, 16, 14, { h: 4.0, wall: wallM, floor: floorM, ceil: mat('stoneDark'),
        doors: [{ side: 'e', at: 0, width: 2.4 }, { side: 'n', at: -4, width: 2.4 }] });
      room(W, -27, -13, 8, 12, { h: 3.4, wall: wallM, floor: floorM, ceil: mat('stoneDark'),
        open: ['s'] });

      torch(W, 3.4, 1.1, -2.6); torch(W, -8, 1.1, -1.2); torch(W, -13.4, 1.1, 1.2);
      torch(W, -18.4, 1.1, -5.4); torch(W, -27.4, 1.1, -17.6);

      // ---- entry room
      const lectern = meshBox(0.7, 1.1, 0.5, mat('woodDark'));
      place(lectern, 3.0, 0.55, 1.6); W.add(lectern);
      W.solid(box(3.0, 1.6, 0.4, 0.3, 0, 1.1));
      putItem(W, 'cr_i1', 'ammo38', 6, 3.0, 1.6, 1.2);

      // ---- coffin hall
      for (let i = 0; i < 8; i++) {
        const cx = -29 + (i % 2) * 12, cz = -5 + Math.floor(i / 2) * 3.4;
        coffin(W, cx, cz, i % 2 ? 0.05 : -0.05, i < 3);
      }
      coffin(W, -23, 5, Math.PI / 2, false);
      putNote(W, 'cr_note', 'cryptNote', -23.0, 5.0, 0.8);
      putItem(W, 'cr_i2', 'herb', 2, -20.0, -1.4);
      barrel(W, -30, 3.4);
      putContainer(W, 'cr_c1', -30, 3.4, [['powder', 2], ['casing', 3]], 'Обыскать бочку');

      // ---- lock room
      const chest = meshBox(1.3, 0.9, 0.8, mat('woodDark'));
      place(chest, -27, 0.45, -17.4); W.add(chest);
      W.solid(box(-27, -17.4, 0.7, 0.45, 0, 0.9));
      const lockPlate = new THREE.Mesh(new THREE.CircleGeometry(0.2, 12), mat('gold'));
      lockPlate.position.set(-27, 0.55, -16.95);
      W.add(lockPlate);
      W.interact({ id: 'cr_lockbox', kind: 'lockbox', x: -27, z: -16.6, y: 0.9,
                   code: LOCK_CODE, mesh: lockPlate,
                   loot: [['ammo38', 10], ['shells', 4]],
                   keys: ['crestLeft', 'millKey'],
                   label: 'Сундук с цифровым замком' });
      putItem(W, 'cr_i3', 'brew', 1, -29.4, -14.0);
      putItem(W, 'cr_i4', 'ring', 1, -24.6, -15.4);

      W.interact({ id: 'cr_exit', kind: 'door', to: 'village', spawn: 'fromCrypt',
                   x: 0, z: 3.6, y: 1.2, label: 'Наверх, в деревню' });

      W.spawn('fromVillage', 0, 2.6, 0);
    },

    enemies: [
      { id: 'cr_g1', type: 'ghoul', x: -22, z: -3, patrol: [[-22, -3], [-27, 3], [-18, 2]] },
      { id: 'cr_g2', type: 'ghoul', x: -12, z: 0, patrol: [[-12, 0], [-8, 0]] },
    ],
    // the lockbox opening wakes what the mel note counted: three coffins too many
    waves: [{ flag: 'lockboxOpen', spawns: [
      { id: 'cr_w1', type: 'ghoul', x: -29, z: -5 },
      { id: 'cr_w2', type: 'ghoul', x: -17, z: -5 },
      { id: 'cr_w3', type: 'stryga', x: -23, z: 4 },
    ] }],
  },

  // =================================================================== mill
  mill: {
    id: 'mill', name: 'Мельница', outdoor: false,
    fog: { color: 0x06060a, density: 0.06 },
    ambient: { color: 0x232a34, intensity: 0.26 }, moon: 0.0, tension: 0.25,
    hint: 'Вторая половина герба — в мучном ларе.',

    build(W) {
      srand(909);
      room(W, 0, 0, 16, 14, { h: 5.2, wall: mat('woodDark'), floor: mat('wood'), ceil: mat('woodDark'),
        doors: [{ side: 'n', at: 0, width: 2.4 }] });
      doorPanel(W, -7.78, 0, Math.PI / 2);
      room(W, 0, -13, 10, 12, { h: 4.0, wall: mat('woodDark'), floor: mat('wood'), ceil: mat('woodDark'),
        open: ['s'] });

      torch(W, -6.4, 1.2, 5.2); torch(W, 6.4, 1.2, -5.2); torch(W, -3.6, 1.2, -16.6);

      // machinery: a millstone, the great gear, the shaft
      const stone = new THREE.Mesh(new THREE.CylinderGeometry(1.7, 1.7, 0.5, 16), mat('stone'));
      stone.position.set(3, 0.7, 1.5); W.add(stone);
      W.solid(box(3, 1.5, 1.7, 1.7, 0, 1.0));
      const base = new THREE.Mesh(new THREE.CylinderGeometry(1.9, 2.0, 0.5, 16), mat('stoneDark'));
      base.position.set(3, 0.25, 1.5); W.add(base);
      const gear = new THREE.Mesh(new THREE.TorusGeometry(1.9, 0.16, 6, 14), mat('woodDark'));
      gear.position.set(-5, 2.4, -4); gear.rotation.y = Math.PI / 2; W.add(gear);
      W.gear = gear;
      const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.16, 8, 8), mat('woodDark'));
      shaft.position.set(-5, 2.4, 0); shaft.rotation.x = Math.PI / 2; W.add(shaft);

      putNote(W, 'ml_note', 'millNote', 3, 1.5, 1.02);

      for (let i = 0; i < 7; i++) {
        const sack = meshBox(0.8, 0.7, 0.8, mat('cloth'));
        place(sack, -6 + (i % 3) * 1.0, 0.35 + (i > 4 ? 0.7 : 0), 4.6 - Math.floor(i / 3) * 1.0, rnd());
        W.add(sack);
        W.solid(box(-6 + (i % 3) * 1.0, 4.6 - Math.floor(i / 3) * 1.0, 0.5, 0.5, 0, 0.8));
      }
      crate(W, 6.4, 4.6); crate(W, 6.4, 3.4, 0.3);
      putContainer(W, 'ml_c1', 6.4, 4.0, [['shells', 4], ['powder', 1]], 'Обыскать ящики');
      putItem(W, 'ml_i1', 'icon_silver', 1, -6.4, -4.6);
      putItem(W, 'ml_i2', 'ammo38', 8, 6.6, -4.4);
      putItem(W, 'ml_i3', 'brew', 1, -6.0, -16.4);
      putItem(W, 'ml_i4', 'holywater', 1, 3.6, -16.0);

      // the flour bin: taking the crest from it is what brings them in
      const bin = meshBox(2.2, 1.1, 1.4, mat('wood'));
      place(bin, 0, 0.55, -16.6); W.add(bin);
      W.solid(box(0, -16.6, 1.2, 0.8, 0, 1.1));
      W.interact({ id: 'ml_crest', kind: 'keyPickup', key: 'crestRight', trigger: 'millAmbush',
                   x: 0, z: -15.6, y: 1.2, mesh: null, label: 'Обыскать мучной ларь' });

      W.interact({ id: 'ml_exit', kind: 'door', to: 'village', spawn: 'fromMill',
                   x: -7.0, z: 0, y: 1.2, label: 'Выйти во двор' });
      W.spawn('fromVillage', -5.6, 0, -Math.PI / 2);
    },

    enemies: [
      { id: 'ml_g1', type: 'ghoul', x: 5, z: -3, patrol: [[5, -3], [0, 4], [6, 5]] },
    ],
    waves: [{ flag: 'millAmbush', spawns: [
      { id: 'ml_w1', type: 'vurdalak', x: -5, z: 5 },
      { id: 'ml_w2', type: 'vurdalak', x: 5.5, z: 5.5 },
      { id: 'ml_w3', type: 'vurdalak', x: 0, z: -10 },
    ] }],
  },

  // ================================================================== manor
  manor: {
    id: 'manor', name: 'Усадьба Мораны', outdoor: false,
    fog: { color: 0x0a0509, density: 0.045 },
    ambient: { color: 0x2c2030, intensity: 0.3 }, moon: 0.16, tension: 0.45,
    hint: 'Сердце у неё снаружи. Бей, когда откроется.',

    build(W) {
      srand(66613);
      // courtyard — open to the sky, and open to the north where the hall's
      // own south wall closes it off
      room(W, 0, 14, 26, 16, { h: 7, wall: mat('stone'), floor: mat('stoneDark'), ceiling: false,
        open: ['n'] });
      doorPanel(W, 0, 21.78, 0, 3.0, 3.4);
      // the hall
      room(W, 0, -7, 30, 26, { h: 7.5, wall: mat('stone'), floor: mat('stoneDark'), ceil: mat('woodDark'),
        doors: [{ side: 's', at: 0, width: 3.6, height: 4.2 }] });

      for (const [x, z] of [[-9, 0], [9, 0], [-9, -10], [9, -10], [-9, -18], [9, -18]]) pillar(W, x, z, 7.5);
      chandelier(W, 0, 5.6, -6); chandelier(W, -7, 5.6, -16); chandelier(W, 7, 5.6, -16);
      torch(W, -11.4, 1.4, 8.4); torch(W, 11.4, 1.4, 8.4);
      torch(W, -12.6, 1.4, 18.6); torch(W, 12.6, 1.4, 18.6);

      // courtyard dressing
      for (let i = 0; i < 5; i++) deadTree(W, -10 + i * 5, 18.4, 0.7);
      const table = meshBox(2.0, 0.9, 1.0, mat('woodDark'));
      place(table, -8, 0.45, 11); W.add(table);
      W.solid(box(-8, 11, 1.0, 0.5, 0, 0.9));
      putNote(W, 'mn_note', 'manorNote', -8, 11, 0.95);
      putItem(W, 'mn_i1', 'shells', 4, 8, 11);
      putItem(W, 'mn_i2', 'brew', 1, 9.4, 16.4);
      barrel(W, -11, 16);
      putContainer(W, 'mn_c1', -11, 16, [['ammo38', 10], ['powder', 2]], 'Обыскать бочку');

      // throne end of the hall
      const dais = meshBox(8, 0.4, 4, mat('stone'));
      place(dais, 0, 0.2, -18); W.add(dais);
      const throne = meshBox(1.4, 2.4, 1.2, mat('woodDark'));
      place(throne, 0, 1.6, -19); W.add(throne);
      W.solid(box(0, -19, 0.8, 0.7, 0.4, 2.8));
      putItem(W, 'mn_i3', 'chalice', 1, 3.4, -17.4, 0.7);
      putItem(W, 'mn_i4', 'holywater', 1, -3.4, -17.4, 0.7);

      W.interact({ id: 'mn_exit', kind: 'door', to: 'village', spawn: 'fromManor',
                   x: 0, z: 21.0, y: 1.2, label: 'Назад в деревню' });
      W.interact({ id: 'mn_shrine', kind: 'shrine', x: -11.4, z: 12.4, y: 1.2, label: 'Помолиться (сохранить игру)' });
      shrine(W, -11.4, 11.6);

      W.spawn('fromVillage', 0, 19.5, 0);
      // crossing into the hall is what brings her down from the ceiling
      W.trigger = { id: 'bossFight', z: 4, spawns: [{ id: 'mn_boss', type: 'morana', x: 0, z: -14 }] };
    },

    enemies: [
      { id: 'mn_g1', type: 'ghoul', x: -8, z: 16, patrol: [[-8, 16], [-10, 20], [-4, 17]] },
      { id: 'mn_g2', type: 'ghoul', x: 9, z: 18, patrol: [[9, 18], [11, 13], [5, 19]] },
    ],
    waves: [],
  },
};
